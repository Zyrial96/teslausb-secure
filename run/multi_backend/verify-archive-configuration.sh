#!/bin/bash -eu
#
# Verify multi-backend archive configuration
#

MULTI_BACKEND_CONFIG="/root/.teslaCamMultiBackendConfig"

echo "Verifying multi-backend configuration..."

if [ ! -r "$MULTI_BACKEND_CONFIG" ]; then
  echo "ERROR: Multi-backend config not found: $MULTI_BACKEND_CONFIG"
  echo "Run configure-archive.sh first"
  exit 1
fi

# Parse configuration
PRIMARY_BACKEND=$(grep "^PRIMARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^PRIMARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')
SECONDARY_BACKEND=$(grep "^SECONDARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^SECONDARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')

if [[ -z "$PRIMARY_BACKEND" ]] || [[ -z "$SECONDARY_BACKEND" ]]; then
  echo "ERROR: PRIMARY_BACKEND or SECONDARY_BACKEND not set in config"
  exit 1
fi

# Validate backend names
if [[ ! "$PRIMARY_BACKEND" =~ ^(cifs|rsync|rclone)$ ]]; then
  echo "ERROR: Invalid PRIMARY_BACKEND: $PRIMARY_BACKEND (must be cifs, rsync, or rclone)"
  exit 1
fi

if [[ ! "$SECONDARY_BACKEND" =~ ^(cifs|rsync|rclone)$ ]]; then
  echo "ERROR: Invalid SECONDARY_BACKEND: $SECONDARY_BACKEND (must be cifs, rsync, or rclone)"
  exit 1
fi

if [ "$PRIMARY_BACKEND" = "$SECONDARY_BACKEND" ]; then
  echo "WARNING: PRIMARY_BACKEND and SECONDARY_BACKEND are the same ($PRIMARY_BACKEND)"
  echo "This may cause conflicts. Consider using different backends."
fi

echo "Multi-backend configuration verified:"
echo "  Primary: $PRIMARY_BACKEND"
echo "  Secondary: $SECONDARY_BACKEND"

# Verify individual backend configurations
echo ""
echo "Verifying primary backend ($PRIMARY_BACKEND)..."

verify_backend_config() {
  local backend="$1"
  local type="$2"
  
  case "$backend" in
    cifs)
      if [ ! -r "/root/.teslaCamArchiveCredentials" ]; then
        echo "ERROR: CIFS credentials not found for $type backend"
        return 1
      fi
      ;;
    rclone)
      if [ ! -r "/root/.teslaCamRcloneConfig" ]; then
        echo "ERROR: Rclone config not found for $type backend"
        return 1
      fi
      if [ ! -r "/root/.config/rclone/rclone.conf" ]; then
        echo "ERROR: rclone.conf not found"
        return 1
      fi
      ;;
    rsync)
      if [ ! -r "/root/.teslaCamRsyncConfig" ]; then
        echo "ERROR: Rsync config not found for $type backend"
        return 1
      fi
      ;;
  esac
  
  echo "  $type backend ($backend): OK"
  return 0
}

verify_backend_config "$PRIMARY_BACKEND" "Primary" || exit 1
verify_backend_config "$SECONDARY_BACKEND" "Secondary" || exit 1

echo ""
echo "All configurations verified successfully!"
