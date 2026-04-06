#!/bin/bash -eu

# FIX: File locking to prevent race conditions
LOCK_FILE="/tmp/teslausb_archive.lock"
exec 200>"$LOCK_FILE"

if ! flock -w 30 200; then
  log "ERROR: Could not acquire archive lock"
  exit 1
fi

trap 'flock -u 200' EXIT

log "Moving clips to rclone archive..."

# FIX: Safe credential parsing instead of 'source'
RCLONE_CONFIG="/root/.teslaCamRcloneConfig"

if [ ! -r "$RCLONE_CONFIG" ]; then
  log "ERROR: Rclone config not found: $RCLONE_CONFIG"
  exit 1
fi

# Parse config safely
rclone_drive=$(grep "^drive=" "$RCLONE_CONFIG" 2>/dev/null | head -1 | sed 's/^drive=//' | tr -d '"'\\'' | tr -d '[:space:]')
rclone_path=$(grep "^path=" "$RCLONE_CONFIG" 2>/dev/null | head -1 | sed 's/^path=//' | tr -d '"'\\'' | tr -d '[:space:]')

# Validate credentials
if [[ -z "$rclone_drive" ]] || [[ -z "$rclone_path" ]]; then
  log "ERROR: Failed to parse rclone config (drive or path missing)"
  exit 1
fi

# Security: Check for injection characters
if [[ "$rclone_drive" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]] || \
   [[ "$rclone_path" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
  log "ERROR: Rclone config contains invalid characters"
  exit 1
fi

NUM_FILES_MOVED=0
FAILED_FILES=0

for file_name in "$CAM_MOUNT"/TeslaCam/saved*; do
  [ -e "$file_name" ] || continue
  
  local_basename=$(basename "$file_name")
  log "Processing $local_basename ..."
  
  # FIX: Check if already archived (avoid duplicates)
  # rclone check is expensive, so we rely on move semantics
  
  # Use rclone move with better error handling
  if rclone --config /root/.config/rclone/rclone.conf \
            move "$file_name" "$rclone_drive:$rclone_path" \
            --log-file=/tmp/rclone-move.log \
            2>>"$LOG_FILE"; then
    
    # Verify file was moved (should not exist locally anymore)
    if [ ! -e "$file_name" ]; then
      log "Successfully archived: $local_basename"
      NUM_FILES_MOVED=$((NUM_FILES_MOVED + 1))
    else
      log "WARNING: $local_basename still exists locally after rclone move"
      FAILED_FILES=$((FAILED_FILES + 1))
    fi
  else
    log "ERROR: Failed to archive $local_basename via rclone"
    FAILED_FILES=$((FAILED_FILES + 1))
  fi
done

log "Archive complete: $NUM_FILES_MOVED file(s) moved, $FAILED_FILES failed"

# Send notification
/root/bin/send-pushover "$NUM_FILES_MOVED"

log "Finished moving clips to rclone archive"
