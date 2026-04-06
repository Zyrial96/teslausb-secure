#!/bin/bash -eu

# FIX: File locking to prevent race conditions
LOCK_FILE="/tmp/teslausb_archive.lock"
exec 200>"$LOCK_FILE"

if ! flock -w 30 200; then
  log "ERROR: Could not acquire archive lock"
  exit 1
fi

trap 'flock -u 200' EXIT

# ==============================================================================
# SMART RETENTION POLICY
# ==============================================================================
# Behalte lokale Clips für RETENTION_DAYS Tage (Default: 7)
# Ältere Clips werden ins Archiv verschoben und lokal gelöscht
RETENTION_DAYS="${RETENTION_DAYS:-7}"
log "Smart Retention: Keeping last $RETENTION_DAYS days locally"

# Berechne Cutoff-Datum im Format für find YYYY-MM-DD
cutoff_date=$(date -d "$RETENTION_DAYS days ago" +%Y%m%d 2>/dev/null || date -v-${RETENTION_DAYS}d +%Y%m%d)
log "Only archiving files older than: $cutoff_date"
# ==============================================================================

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

# Count files before rsync (nur die, die archiviert werden sollen)
# Finde Dateien älter als RETENTION_DAYS
files_to_archive=$(find /mnt/cam/TeslaCam/saved* -type f ! -newermt "$RETENTION_DAYS days ago" 2>/dev/null | wc -l)
files_before=$(find /mnt/cam/TeslaCam/saved* -type f 2>/dev/null | wc -l)
files_skipped=$((files_before - files_to_archive))

log "Files to archive: $files_to_archive, Files to keep locally: $files_skipped"

# SMART RETENTION: Erstelle Liste der zu archivierenden Dateien (älter als RETENTION_DAYS)
file_list=$(mktemp /tmp/rsync_files.XXXXXX)
trap 'rm -f $file_list $rsync_temp_dir; flock -u 200' EXIT

# Finde alle Dateien älter als RETENTION_DAYS und speichere relative Pfade
find /mnt/cam/TeslaCam/saved* -type f ! -newermt "$RETENTION_DAYS days ago" 2>/dev/null | \
  sed 's|/mnt/cam/||' > "$file_list"

if [ ! -s "$file_list" ]; then
  log "No files older than $RETENTION_DAYS days to archive."
  rm -f "$file_list"
  exit 0
fi

log "Found $(wc -l < "$file_list") files to archive"

# FIX: Use flock for atomic rsync operation with better error handling
# --partial allows resuming interrupted transfers
# --temp-dir ensures atomic moves on destination
rsync_temp_dir=$(mktemp -d /tmp/rsync_temp.XXXXXX)
trap 'rm -rf $rsync_temp_dir $file_list; flock -u 200' EXIT

if rsync -auzvh --no-perms --partial --temp-dir="$rsync_temp_dir" \
           --stats --log-file=/tmp/archive-rsync-cmd.log \
           --files-from="$file_list" \
           /mnt/cam/ \
           "${rsync_user}@${rsync_server}:${rsync_path}" 2>>"$LOG_FILE"; then
  
  # Parse number of transferred files from rsync stats
  num_files_moved=$(grep "Number of regular files transferred" /tmp/archive-rsync-cmd.log 2>/dev/null | awk '{print $NF}' || echo 0)
  
  log "Rsync completed: $num_files_moved file(s) transferred"
  
  # SMART RETENTION: Lösche erfolgreich archivierte lokale Dateien
  if [ "$num_files_moved" -gt 0 ]; then
    log "Removing archived files from local storage..."
    while IFS= read -r rel_path; do
      local_file="/mnt/cam/$rel_path"
      if [ -f "$local_file" ]; then
        rm -f "$local_file" && log "Deleted: $rel_path" || log "Failed to delete: $rel_path"
      fi
    done < "$file_list"
    log "Local cleanup complete."
  fi
  
  # Send notification
  /root/bin/send-pushover "$num_files_moved" 2>/dev/null || true
  /root/bin/send-discord "$num_files_moved" 2>/dev/null || true
  
  if [ "$num_files_moved" -gt 0 ]; then
    log "Successfully synced and removed $num_files_moved files through rsync."
  else
    log "No new files to archive through rsync."
  fi
else
  log "ERROR: Rsync failed with exit code $?"
  rm -rf "$rsync_temp_dir" "$file_list"
  exit 1
fi

rm -rf "$rsync_temp_dir" "$file_list"
