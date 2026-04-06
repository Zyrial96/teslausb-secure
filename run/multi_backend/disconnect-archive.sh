#!/bin/bash -eu
#
# Disconnect archive backends
#

MULTI_BACKEND_CONFIG="/root/.teslaCamMultiBackendConfig"

if [ ! -r "$MULTI_BACKEND_CONFIG" ]; then
  exit 0
fi

# Parse configuration
PRIMARY_BACKEND=$(grep "^PRIMARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^PRIMARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')

# Disconnect CIFS if mounted
if [ "$PRIMARY_BACKEND" = "cifs" ]; then
  if findmnt --mountpoint /mnt/archive > /dev/null 2>&1; then
    log "Unmounting CIFS archive..."
    umount /mnt/archive 2>>"$LOG_FILE" || log "WARNING: Failed to unmount CIFS"
  fi
fi

# Clean up temp files
rm -f /tmp/primary_done_*.marker
rm -f /tmp/archive_in_progress

log "Archive backends disconnected"
