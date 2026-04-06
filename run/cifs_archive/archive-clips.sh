#!/bin/bash -eu

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

log "Moving clips to archive..."

NUM_FILES_MOVED=0
FAILED_FILES=0

for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
  [ -e "$file_name" ] || continue
  
  local_basename=$(basename "$file_name")
  log "Processing $local_basename ..."
  
  # FIX: Atomic move operation with verification
  # 1. Copy to temp location on destination
  # 2. Sync to ensure data is written
  # 3. Move temp to final location (atomic)
  # 4. Remove source only after verification
  
  temp_dest="$ARCHIVE_MOUNT/.${local_basename}.tmp.$$"
  final_dest="$ARCHIVE_MOUNT/$local_basename"
  
  # Check if file already exists in archive (skip if yes)
  if [ -e "$final_dest" ]; then
    log "WARNING: $local_basename already exists in archive, skipping"
    continue
  fi
  
  # Copy with progress tracking
  if cp -- "$file_name" "$temp_dest" 2>>"$LOG_FILE"; then
    # Sync to ensure data is physically written
    sync
    
    # Verify copy success (compare sizes)
    orig_size=$(stat -c%s "$file_name" 2>/dev/null || echo 0)
    copy_size=$(stat -c%s "$temp_dest" 2>/dev/null || echo 0)
    
    if [ "$orig_size" -eq "$copy_size" ] && [ "$orig_size" -gt 0 ]; then
      # Atomic move to final destination
      if mv -- "$temp_dest" "$final_dest" 2>>"$LOG_FILE"; then
        # Now safe to remove source
        if rm -- "$file_name" 2>>"$LOG_FILE"; then
          log "Successfully archived: $local_basename"
          NUM_FILES_MOVED=$((NUM_FILES_MOVED + 1))
        else
          log "ERROR: Failed to remove source after archive: $local_basename"
          FAILED_FILES=$((FAILED_FILES + 1))
        fi
      else
        log "ERROR: Failed to finalize archive for: $local_basename"
        rm -f "$temp_dest"
        FAILED_FILES=$((FAILED_FILES + 1))
      fi
    else
      log "ERROR: Size mismatch for $local_basename (orig: $orig_size, copy: $copy_size)"
      rm -f "$temp_dest"
      FAILED_FILES=$((FAILED_FILES + 1))
    fi
  else
    log "ERROR: Failed to copy $local_basename to temp location"
    FAILED_FILES=$((FAILED_FILES + 1))
  fi
done

log "Archive complete: $NUM_FILES_MOVED file(s) moved, $FAILED_FILES failed"

# Send notification only if files were actually moved
if [ "$NUM_FILES_MOVED" -gt 0 ]; then
  /root/bin/send-pushover "$NUM_FILES_MOVED"
fi

log "Finished moving clips to archive."
