#!/bin/bash -eu
#
# Check if archive backends are reachable
#

MULTI_BACKEND_CONFIG="/root/.teslaCamMultiBackendConfig"

# If no multi-backend config, fall back to single-backend check
if [ ! -r "$MULTI_BACKEND_CONFIG" ]; then
  # Check if single-backend archive-is-reachable exists
  if [ -x "/root/bin/archive-is-reachable.sh" ]; then
    exec /root/bin/archive-is-reachable.sh "$@"
  fi
  exit 1
fi

# Parse configuration
PRIMARY_BACKEND=$(grep "^PRIMARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^PRIMARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')
SECONDARY_BACKEND=$(grep "^SECONDARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^SECONDARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')

# For multi-backend, we primarily care if PRIMARY is reachable
# Secondary is typically cloud/remote and may have intermittent connectivity

check_backend_reachable() {
  local backend="$1"
  
  case "$backend" in
    cifs)
      # Check CIFS server
      if [ -r "/root/.teslaCamArchiveConfig" ]; then
        archiveserver=$(grep "^archiveserver=" /root/.teslaCamArchiveConfig | sed 's/^archiveserver=//' | tr -d '[:space:]')
        if [ -n "$archiveserver" ]; then
          # Try ping
          if ping -c 1 -W 2 "$archiveserver" > /dev/null 2>&1; then
            return 0
          fi
        fi
      fi
      return 1
      ;;
      
    rclone)
      # For rclone, check DNS connectivity (cloud)
      if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        return 0
      fi
      return 1
      ;;
      
    rsync)
      # Check SSH server
      if [ -r "/root/.teslaCamRsyncConfig" ]; then
        rsync_server=$(grep "^server=" /root/.teslaCamRsyncConfig | sed 's/^server=//' | tr -d '[:space:]')
        if [ -n "$rsync_server" ]; then
          if ping -c 1 -W 2 "$rsync_server" > /dev/null 2>&1; then
            return 0
          fi
        fi
      fi
      return 1
      ;;
  esac
  
  return 1
}

# Check primary backend - this is required
if check_backend_reachable "$PRIMARY_BACKEND"; then
  # Primary is reachable - we're good to start archiving
  # Secondary will be attempted but is not required for starting
  exit 0
fi

# Primary not reachable
exit 1
