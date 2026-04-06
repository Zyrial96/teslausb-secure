#!/bin/bash -eu

# FIX: File locking to prevent race conditions
LOCK_FILE="/tmp/teslausb_archive.lock"
exec 200>"$LOCK_FILE"

if ! flock -w 30 200; then
  log "ERROR: Could not acquire archive lock"
  exit 1
fi

trap 'flock -u 200' EXIT

log "Archiving through rsync..."

# FIX: Safe credential parsing instead of 'source'
RSYNC_CONFIG="/root/.teslaCamRsyncConfig"

if [ ! -r "$RSYNC_CONFIG" ]; then
  log "ERROR: Rsync config not found: $RSYNC_CONFIG"
  exit 1
fi

# Parse config safely (key=value format)
rsync_user=$(grep "^user=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^user=//' | tr -d '"'\\'' | tr -d '[:space:]')
rsync_server=$(grep "^server=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^server=//' | tr -d '"'\\'' | tr -d '[:space:]')
rsync_path=$(grep "^path=" "$RSYNC_CONFIG" 2>/dev/null | head -1 | sed 's/^path=//' | tr -d '"'\\'' | tr -d '[:space:]')

# Validate credentials
if [[ -z "$rsync_user" ]] || [[ -z "$rsync_server" ]] || [[ -z "$rsync_path" ]]; then
  log "ERROR: Failed to parse rsync config (user, server, or path missing)"
  exit 1
fi

# Security: Check for injection characters
if [[ "$rsync_user" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]] || \
   [[ "$rsync_server" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]] || \
   [[ "$rsync_path" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
  log "ERROR: Rsync config contains invalid characters"
  exit 1
fi

# Count files before rsync
files_before=$(find /mnt/cam/TeslaCam/saved* -type f 2>/dev/null | wc -l)

# FIX: Use flock for atomic rsync operation with better error handling
# --partial allows resuming interrupted transfers
# --temp-dir ensures atomic moves on destination
rsync_temp_dir=$(mktemp -d /tmp/rsync_temp.XXXXXX)
trap 'rm -rf $rsync_temp_dir; flock -u 200' EXIT

if rsync -auzvh --no-perms --partial --temp-dir="$rsync_temp_dir" \
           --stats --log-file=/tmp/archive-rsync-cmd.log \
           "/mnt/cam/TeslaCam/saved*" \
           "${rsync_user}@${rsync_server}:${rsync_path}" 2>>"$LOG_FILE"; then
  
  # Parse number of transferred files from rsync stats
  num_files_moved=$(grep "Number of regular files transferred" /tmp/archive-rsync-cmd.log 2>/dev/null | awk '{print $NF}' || echo 0)
  
  log "Rsync completed: $num_files_moved file(s) transferred"
  
  # Send notification
  /root/bin/send-pushover "$num_files_moved"
  
  if [ "$num_files_moved" -gt 0 ]; then
    log "Successfully synced files through rsync."
  else
    log "No new files to archive through rsync."
  fi
else
  log "ERROR: Rsync failed with exit code $?"
  exit 1
fi

rm -rf "$rsync_temp_dir"
