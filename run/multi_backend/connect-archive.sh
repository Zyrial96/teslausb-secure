#!/bin/bash -eu
#
# Connect both archive backends (prepare for archiving)
#

MULTI_BACKEND_CONFIG="/root/.teslaCamMultiBackendConfig"

if [ ! -r "$MULTI_BACKEND_CONFIG" ]; then
  echo "ERROR: Multi-backend config not found"
  exit 1
fi

# Parse configuration
PRIMARY_BACKEND=$(grep "^PRIMARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^PRIMARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')
SECONDARY_BACKEND=$(grep "^SECONDARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^SECONDARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')

# Function to connect a backend
connect_backend() {
  local backend="$1"
  local type="$2"
  
  log "Connecting $type backend: $backend"
  
  case "$backend" in
    cifs)
      # CIFS needs mount
      if [ -d "/mnt/archive" ]; then
        # Read CIFS config
        CIFS_CONFIG="/root/.teslaCamArchiveConfig"
        if [ -r "$CIFS_CONFIG" ]; then
          archiveserver=$(grep "^archiveserver=" "$CIFS_CONFIG" | sed 's/^archiveserver=//')
          sharename=$(grep "^sharename=" "$CIFS_CONFIG" | sed 's/^sharename=//')
          
          if ! findmnt --mountpoint /mnt/archive > /dev/null 2>&1; then
            mount -t cifs "//$archiveserver/$sharename" /mnt/archive \
                  -o credentials=/root/.teslaCamArchiveCredentials,iocharset=utf8,file_mode=0777,dir_mode=0777,vers=3.0 \
                  2>>"$LOG_FILE" || log "WARNING: Failed to mount CIFS share"
          fi
        fi
      fi
      ;;
      
    rclone)
      # Rclone doesn't need pre-connection, just verify config exists
      if [ ! -r "/root/.config/rclone/rclone.conf" ]; then
        log "WARNING: rclone.conf not found"
      else
        log "Rclone config verified"
      fi
      ;;
      
    rsync)
      # Rsync doesn't need pre-connection, verify SSH key if needed
      log "Rsync backend ready (uses SSH keys)"
      ;;
  esac
}

# Connect primary (may need mount for CIFS)
connect_backend "$PRIMARY_BACKEND" "Primary"

# Secondary typically doesn't need connection (rclone/rsync use their own connections)
log "Secondary backend ($SECONDARY_BACKEND) will connect on-demand during archive"
