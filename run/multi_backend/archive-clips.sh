#!/bin/bash -eu
#
# Multi-Backend Archive Script for TeslaUSB
# Archives clips to PRIMARY_BACKEND and SECONDARY_BACKEND simultaneously
# Both backends must succeed for "complete" status
#

# FIX: File locking to prevent race conditions
LOCK_FILE="/tmp/teslausb_archive.lock"
exec 200>"$LOCK_FILE"

# Try to acquire lock with timeout (30 seconds)
if ! flock -w 30 200; then
  log "ERROR: Could not acquire archive lock (another instance running?)"
  exit 1
fi

# Ensure lock is released on exit
trap 'flock -u 200; rm -f /tmp/archive_in_progress' EXIT

# Mark archive as in progress (for monitoring)
touch /tmp/archive_in_progress

# Load configuration
MULTI_BACKEND_CONFIG="/root/.teslaCamMultiBackendConfig"

if [ ! -r "$MULTI_BACKEND_CONFIG" ]; then
  log "ERROR: Multi-backend config not found: $MULTI_BACKEND_CONFIG"
  log "Falling back to single-backend mode..."
  /root/bin/archive-clips.sh
  exit $?
fi

# Parse multi-backend configuration
PRIMARY_BACKEND=$(grep "^PRIMARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^PRIMARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')
SECONDARY_BACKEND=$(grep "^SECONDARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^SECONDARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')

if [[ -z "$PRIMARY_BACKEND" ]] || [[ -z "$SECONDARY_BACKEND" ]]; then
  log "ERROR: Multi-backend config incomplete (PRIMARY_BACKEND or SECONDARY_BACKEND missing)"
  log "Falling back to single-backend mode..."
  /root/bin/archive-clips.sh
  exit $?
fi

# Security: Validate backend names (only allowed: cifs, rsync, rclone)
if [[ ! "$PRIMARY_BACKEND" =~ ^(cifs|rsync|rclone)$ ]] || \
   [[ ! "$SECONDARY_BACKEND" =~ ^(cifs|rsync|rclone)$ ]]; then
  log "ERROR: Invalid backend configuration. Allowed values: cifs, rsync, rclone"
  exit 1
fi

log "=========================================="
log "Starting MULTI-BACKEND archival process..."
log "Primary: $PRIMARY_BACKEND | Secondary: $SECONDARY_BACKEND"
log "=========================================="

# Track results for both backends
PRIMARY_SUCCESS=false
SECONDARY_SUCCESS=false
NUM_FILES_PRIMARY=0
NUM_FILES_SECONDARY=0
FAILED_FILES_PRIMARY=0
FAILED_FILES_SECONDARY=0

# ============================================================================
# PRIMARY BACKEND ARCHIVE FUNCTION
# ============================================================================
archive_to_primary() {
  local backend="$1"
  log "[PRIMARY] Starting archive to $backend..."
  
  local num_moved=0
  local num_failed=0
  
  case "$backend" in
    cifs)
      # CIFS backend - uses ARCHIVE_MOUNT
      if [ ! -d "$ARCHIVE_MOUNT" ]; then
        log "[PRIMARY-CIFS] ERROR: Archive mount not available: $ARCHIVE_MOUNT"
        return 1
      fi
      
      for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
        [ -e "$file_name" ] || continue
        
        local local_basename=$(basename "$file_name")
        log "[PRIMARY-CIFS] Processing $local_basename ..."
        
        local temp_dest="$ARCHIVE_MOUNT/.${local_basename}.tmp.$$"
        local final_dest="$ARCHIVE_MOUNT/$local_basename"
        
        # Skip if already exists
        if [ -e "$final_dest" ]; then
          log "[PRIMARY-CIFS] WARNING: $local_basename already exists, skipping"
          continue
        fi
        
        # Copy with verification
        if cp -- "$file_name" "$temp_dest" 2>>"$LOG_FILE"; then
          sync
          
          local orig_size=$(stat -c%s "$file_name" 2>/dev/null || echo 0)
          local copy_size=$(stat -c%s "$temp_dest" 2>/dev/null || echo 0)
          
          if [ "$orig_size" -eq "$copy_size" ] && [ "$orig_size" -gt 0 ]; then
            if mv -- "$temp_dest" "$final_dest" 2>>"$LOG_FILE"; then
              log "[PRIMARY-CIFS] SUCCESS: $local_basename archived to primary"
              num_moved=$((num_moved + 1))
            else
              log "[PRIMARY-CIFS] ERROR: Failed to finalize $local_basename"
              rm -f "$temp_dest"
              num_failed=$((num_failed + 1))
            fi
          else
            log "[PRIMARY-CIFS] ERROR: Size mismatch for $local_basename"
            rm -f "$temp_dest"
            num_failed=$((num_failed + 1))
          fi
        else
          log "[PRIMARY-CIFS] ERROR: Failed to copy $local_basename"
          num_failed=$((num_failed + 1))
        fi
      done
      ;;
      
    rclone)
      # Rclone backend
      local RCLONE_CONFIG="/root/.teslaCamRcloneConfig"
      
      if [ ! -r "$RCLONE_CONFIG" ]; then
        log "[PRIMARY-RCLONE] ERROR: Rclone config not found"
        return 1
      fi
      
      local rclone_drive=$(grep "^drive=" "$RCLONE_CONFIG" 2>/dev/null | head -1 | sed 's/^drive=//' | tr -d '"' | tr -d '[:space:]')
      local rclone_path=$(grep "^path=" "$RCLONE_CONFIG" 2>/dev/null | head -1 | sed 's/^path=//' | tr -d '"' | tr -d '[:space:]')
      
      if [[ -z "$rclone_drive" ]] || [[ -z "$rclone_path" ]]; then
        log "[PRIMARY-RCLONE] ERROR: Invalid rclone config"
        return 1
      fi
      
      # Security check
      if [[ "$rclone_drive" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]] || \
         [[ "$rclone_path" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
        log "[PRIMARY-RCLONE] ERROR: Config contains invalid characters"
        return 1
      fi
      
      for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
        [ -e "$file_name" ] || continue
        
        local local_basename=$(basename "$file_name")
        log "[PRIMARY-RCLONE] Processing $local_basename ..."
        
        # Create a marker file to track completion
        local marker_file="/tmp/primary_done_${local_basename}.marker"
        
        if rclone --config /root/.config/rclone/rclone.conf \
                  copy "$file_name" "$rclone_drive:$rclone_path" \
                  --log-file=/tmp/rclone-primary.log 2>>"$LOG_FILE"; then
          
          # Verify with ls
          if rclone --config /root/.config/rclone/rclone.conf \
                    ls "$rclone_drive:$rclone_path/$local_basename" >/dev/null 2>&1; then
            log "[PRIMARY-RCLONE] SUCCESS: $local_basename archived to primary"
            touch "$marker_file"
            num_moved=$((num_moved + 1))
          else
            log "[PRIMARY-RCLONE] ERROR: Verification failed for $local_basename"
            num_failed=$((num_failed + 1))
          fi
        else
          log "[PRIMARY-RCLONE] ERROR: Failed to archive $local_basename"
          num_failed=$((num_failed + 1))
        fi
      done
      ;;
      
    rsync)
      # Rsync backend
      local RSYNC_CONFIG="/root/.teslaCamRsyncConfig"
      
      if [ ! -r "$RSYNC_CONFIG" ]; then
        log "[PRIMARY-RSYNC] ERROR: Rsync config not found"
        return 1
      fi
      
      local rsync_user=$(grep "^user=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^user=//' | tr -d '"' | tr -d '[:space:]')
      local rsync_server=$(grep "^server=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^server=//' | tr -d '"' | tr -d '[:space:]')
      local rsync_path=$(grep "^path=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^path=//' | tr -d '"' | tr -d '[:space:]')
      
      if [[ -z "$rsync_user" ]] || [[ -z "$rsync_server" ]] || [[ -z "$rsync_path" ]]; then
        log "[PRIMARY-RSYNC] ERROR: Invalid rsync config"
        return 1
      fi
      
      # Security check
      if [[ "$rsync_user" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]] || \
         [[ "$rsync_server" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]] || \
         [[ "$rsync_path" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
        log "[PRIMARY-RSYNC] ERROR: Config contains invalid characters"
        return 1
      fi
      
      local rsync_temp_dir=$(mktemp -d /tmp/rsync_primary_temp.XXXXXX)
      
      for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
        [ -e "$file_name" ] || continue
        
        local local_basename=$(basename "$file_name")
        log "[PRIMARY-RSYNC] Processing $local_basename ..."
        
        # Use rsync for single file with temp dir
        if rsync -auzvh --no-perms --partial --temp-dir="$rsync_temp_dir" \
                   "$file_name" "${rsync_user}@${rsync_server}:${rsync_path}/" \
                   2>>"$LOG_FILE"; then
          log "[PRIMARY-RSYNC] SUCCESS: $local_basename archived to primary"
          touch "/tmp/primary_done_${local_basename}.marker"
          num_moved=$((num_moved + 1))
        else
          log "[PRIMARY-RSYNC] ERROR: Failed to archive $local_basename"
          num_failed=$((num_failed + 1))
        fi
      done
      
      rm -rf "$rsync_temp_dir"
      ;;
  esac
  
  NUM_FILES_PRIMARY=$num_moved
  FAILED_FILES_PRIMARY=$num_failed
  
  if [ "$num_failed" -eq 0 ] && [ "$num_moved" -gt 0 ]; then
    return 0
  elif [ "$num_failed" -eq 0 ] && [ "$num_moved" -eq 0 ]; then
    log "[PRIMARY] No files to archive"
    return 0
  else
    return 1
  fi
}

# ============================================================================
# SECONDARY BACKEND ARCHIVE FUNCTION
# ============================================================================
archive_to_secondary() {
  local backend="$1"
  log "[SECONDARY] Starting archive to $backend..."
  
  local num_moved=0
  local num_failed=0
  
  case "$backend" in
    cifs)
      log "[SECONDARY-CIFS] CIFS as secondary backend not fully supported (would need separate mount)"
      log "[SECONDARY-CIFS] Consider using rclone or rsync as secondary backend"
      return 1
      ;;
      
    rclone)
      # Rclone backend for secondary
      local RCLONE_CONFIG="/root/.teslaCamRcloneConfig"
      
      if [ ! -r "$RCLONE_CONFIG" ]; then
        log "[SECONDARY-RCLONE] ERROR: Rclone config not found"
        return 1
      fi
      
      local rclone_drive=$(grep "^drive=" "$RCLONE_CONFIG" 2>/dev/null | head -1 | sed 's/^drive=//' | tr -d '"' | tr -d '[:space:]')
      local rclone_path=$(grep "^path=" "$RCLONE_CONFIG" 2>/dev/null | head -1 | sed 's/^path=//' | tr -d '"' | tr -d '[:space:]')
      
      if [[ -z "$rclone_drive" ]] || [[ -z "$rclone_path" ]]; then
        log "[SECONDARY-RCLONE] ERROR: Invalid rclone config"
        return 1
      fi
      
      for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
        [ -e "$file_name" ] || continue
        
        local local_basename=$(basename "$file_name")
        
        # Only archive if primary succeeded (marker file exists)
        if [ ! -f "/tmp/primary_done_${local_basename}.marker" ]; then
          log "[SECONDARY-RCLONE] Skipping $local_basename (primary failed or not done)"
          continue
        fi
        
        log "[SECONDARY-RCLONE] Processing $local_basename ..."
        
        if rclone --config /root/.config/rclone/rclone.conf \
                  copy "$file_name" "$rclone_drive:$rclone_path" \
                  --log-file=/tmp/rclone-secondary.log 2>>"$LOG_FILE"; then
          
          if rclone --config /root/.config/rclone/rclone.conf \
                    ls "$rclone_drive:$rclone_path/$local_basename" >/dev/null 2>&1; then
            log "[SECONDARY-RCLONE] SUCCESS: $local_basename archived to secondary"
            num_moved=$((num_moved + 1))
          else
            log "[SECONDARY-RCLONE] ERROR: Verification failed for $local_basename"
            num_failed=$((num_failed + 1))
          fi
        else
          log "[SECONDARY-RCLONE] ERROR: Failed to archive $local_basename"
          num_failed=$((num_failed + 1))
        fi
      done
      ;;
      
    rsync)
      # Rsync backend for secondary
      local RSYNC_CONFIG="/root/.teslaCamRsyncConfig"
      
      if [ ! -r "$RSYNC_CONFIG" ]; then
        log "[SECONDARY-RSYNC] ERROR: Rsync config not found"
        return 1
      fi
      
      local rsync_user=$(grep "^user=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^user=//' | tr -d '"' | tr -d '[:space:]')
      local rsync_server=$(grep "^server=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^server=//' | tr -d '"' | tr -d '[:space:]')
      local rsync_path=$(grep "^path=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^path=//' | tr -d '"' | tr -d '[:space:]')
      
      if [[ -z "$rsync_user" ]] || [[ -z "$rsync_server" ]] || [[ -z "$rsync_path" ]]; then
        log "[SECONDARY-RSYNC] ERROR: Invalid rsync config"
        return 1
      fi
      
      local rsync_temp_dir=$(mktemp -d /tmp/rsync_secondary_temp.XXXXXX)
      
      for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
        [ -e "$file_name" ] || continue
        
        local local_basename=$(basename "$file_name")
        
        # Only archive if primary succeeded
        if [ ! -f "/tmp/primary_done_${local_basename}.marker" ]; then
          log "[SECONDARY-RSYNC] Skipping $local_basename (primary failed or not done)"
          continue
        fi
        
        log "[SECONDARY-RSYNC] Processing $local_basename ..."
        
        if rsync -auzvh --no-perms --partial --temp-dir="$rsync_temp_dir" \
                   "$file_name" "${rsync_user}@${rsync_server}:${rsync_path}/" \
                   2>>"$LOG_FILE"; then
          log "[SECONDARY-RSYNC] SUCCESS: $local_basename archived to secondary"
          num_moved=$((num_moved + 1))
        else
          log "[SECONDARY-RSYNC] ERROR: Failed to archive $local_basename"
          num_failed=$((num_failed + 1))
        fi
      done
      
      rm -rf "$rsync_temp_dir"
      ;;
  esac
  
  NUM_FILES_SECONDARY=$num_moved
  FAILED_FILES_SECONDARY=$num_failed
  
  if [ "$num_failed" -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# CLEANUP FUNCTION - removes files only if BOTH backends succeeded
# ============================================================================
cleanup_source_files() {
  log "[CLEANUP] Checking for files to remove..."
  
  local removed_count=0
  
  for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
    [ -e "$file_name" ] || continue
    
    local local_basename=$(basename "$file_name")
    local marker_file="/tmp/primary_done_${local_basename}.marker"
    
    # Only remove if primary succeeded AND we're in complete status
    if [ "$PRIMARY_SUCCESS" = true ] && [ "$SECONDARY_SUCCESS" = true ]; then
      if [ -f "$marker_file" ]; then
        if rm -- "$file_name" 2>>"$LOG_FILE"; then
          log "[CLEANUP] Removed source: $local_basename"
          removed_count=$((removed_count + 1))
        else
          log "[CLEANUP] ERROR: Failed to remove $local_basename"
        fi
      fi
    else
      log "[CLEANUP] Keeping $local_basename (incomplete status)"
    fi
    
    # Clean up marker files
    rm -f "$marker_file"
  done
  
  log "[CLEANUP] Removed $removed_count source file(s)"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Archive to primary backend first
if archive_to_primary "$PRIMARY_BACKEND"; then
  PRIMARY_SUCCESS=true
  log "[RESULT] Primary backend ($PRIMARY_BACKEND): SUCCESS ($NUM_FILES_PRIMARY files)"
else
  log "[RESULT] Primary backend ($PRIMARY_BACKEND): FAILED"
fi

# Archive to secondary backend (only files that succeeded on primary)
if archive_to_secondary "$SECONDARY_BACKEND"; then
  SECONDARY_SUCCESS=true
  log "[RESULT] Secondary backend ($SECONDARY_BACKEND): SUCCESS ($NUM_FILES_SECONDARY files)"
else
  log "[RESULT] Secondary backend ($SECONDARY_BACKEND): FAILED"
fi

# Clean up source files only if BOTH succeeded
cleanup_source_files

# Calculate overall status
TOTAL_FAILED=$((FAILED_FILES_PRIMARY + FAILED_FILES_SECONDARY))

# ============================================================================
# FINAL STATUS REPORT
# ============================================================================
log "=========================================="
log "MULTI-BACKUP ARCHIVE SUMMARY"
log "=========================================="
log "Primary ($PRIMARY_BACKEND):   $NUM_FILES_PRIMARY files, $FAILED_FILES_PRIMARY failed"
log "Secondary ($SECONDARY_BACKEND): $NUM_FILES_SECONDARY files, $FAILED_FILES_SECONDARY failed"
log "=========================================="

if [ "$PRIMARY_SUCCESS" = true ] && [ "$SECONDARY_SUCCESS" = true ]; then
  log "OVERALL STATUS: COMPLETE ✓ (Both backends successful)"
  
  # Send notification
  /root/bin/send-pushover "$NUM_FILES_PRIMARY"
  
  # Mark as complete for monitoring
  touch /tmp/archive_complete
  rm -f /tmp/archive_partial /tmp/archive_failed
  
  exit 0
elif [ "$PRIMARY_SUCCESS" = true ] && [ "$SECONDARY_SUCCESS" = false ]; then
  log "OVERALL STATUS: PARTIAL ⚠ (Primary OK, Secondary failed)"
  
  # Send notification about partial success
  /root/bin/send-pushover "$NUM_FILES_PRIMARY"
  
  touch /tmp/archive_partial
  rm -f /tmp/archive_complete /tmp/archive_failed
  
  # Return error since secondary failed
  exit 1
else
  log "OVERALL STATUS: FAILED ✗ (Primary failed)"
  
  touch /tmp/archive_failed
  rm -f /tmp/archive_complete /tmp/archive_partial
  
  exit 1
fi
