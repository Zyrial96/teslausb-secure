#!/bin/bash -eu
#
# Configure multi-backend archive
#

echo "=================================="
echo "Multi-Backend Configuration"
echo "=================================="
echo ""
echo "This will configure TeslaUSB to archive to TWO backends:"
echo "  - PRIMARY: Local NAS (CIFS/SMB)"
echo "  - SECONDARY: Cloud (rclone) or remote server (rsync)"
echo ""
echo "Both backends must succeed for 'complete' status."
echo ""

# Check required environment variables
if [[ -z "${PRIMARY_BACKEND:-}" ]] || [[ -z "${SECONDARY_BACKEND:-}" ]]; then
  echo "ERROR: PRIMARY_BACKEND and SECONDARY_BACKEND must be set"
  echo ""
  echo "Example:"
  echo "  export PRIMARY_BACKEND=cifs"
  echo "  export SECONDARY_BACKEND=rclone"
  echo ""
  echo "Allowed values: cifs, rsync, rclone"
  exit 1
fi

# Validate backends
if [[ ! "$PRIMARY_BACKEND" =~ ^(cifs|rsync|rclone)$ ]]; then
  echo "ERROR: Invalid PRIMARY_BACKEND: $PRIMARY_BACKEND"
  echo "Allowed: cifs, rsync, rclone"
  exit 1
fi

if [[ ! "$SECONDARY_BACKEND" =~ ^(cifs|rsync|rclone)$ ]]; then
  echo "ERROR: Invalid SECONDARY_BACKEND: $SECONDARY_BACKEND"
  echo "Allowed: cifs, rsync, rclone"
  exit 1
fi

if [ "$PRIMARY_BACKEND" = "$SECONDARY_BACKEND" ]; then
  echo "WARNING: Both backends are set to $PRIMARY_BACKEND"
  echo "This may cause conflicts unless using different destinations."
  echo ""
  read -p "Continue anyway? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo "Configuring backends:"
echo "  Primary: $PRIMARY_BACKEND"
echo "  Secondary: $SECONDARY_BACKEND"
echo ""

# Create multi-backend config
MULTI_BACKEND_CONFIG="/root/.teslaCamMultiBackendConfig"

echo "Creating multi-backend config: $MULTI_BACKEND_CONFIG"
cat > "$MULTI_BACKEND_CONFIG" << EOF
# TeslaUSB Multi-Backend Configuration
# Generated: $(date)
PRIMARY_BACKEND=$PRIMARY_BACKEND
SECONDARY_BACKEND=$SECONDARY_BACKEND
EOF

chmod 600 "$MULTI_BACKEND_CONFIG"
echo "Config saved."
echo ""

# Configure individual backends
configure_backend() {
  local backend="$1"
  local type="$2"
  
  echo "Configuring $type backend: $backend"
  
  case "$backend" in
    cifs)
      if [[ -z "${archiveserver:-}" ]] || [[ -z "${sharename:-}" ]] || \
         [[ -z "${shareuser:-}" ]] || [[ -z "${sharepassword:-}" ]]; then
        echo "ERROR: CIFS requires archiveserver, sharename, shareuser, sharepassword"
        exit 1
      fi
      
      # Write CIFS credentials
      CREDENTIALS_FILE="/root/.teslaCamArchiveCredentials"
      echo "username=$shareuser" > "$CREDENTIALS_FILE"
      echo "password=$sharepassword" >> "$CREDENTIALS_FILE"
      echo "domain=${domain:-WORKGROUP}" >> "$CREDENTIALS_FILE"
      chmod 600 "$CREDENTIALS_FILE"
      
      # Write CIFS archive config
      CIFS_CONFIG="/root/.teslaCamArchiveConfig"
      echo "archiveserver=$archiveserver" > "$CIFS_CONFIG"
      echo "sharename=$sharename" >> "$CIFS_CONFIG"
      chmod 600 "$CIFS_CONFIG"
      
      echo "  CIFS configured: //$archiveserver/$sharename"
      ;;
      
    rclone)
      if [[ -z "${RCLONE_DRIVE:-}" ]] || [[ -z "${RCLONE_PATH:-}" ]]; then
        echo "ERROR: Rclone requires RCLONE_DRIVE and RCLONE_PATH"
        exit 1
      fi
      
      # Write rclone config
      RCLONE_CONFIG="/root/.teslaCamRcloneConfig"
      echo "drive=$RCLONE_DRIVE" > "$RCLONE_CONFIG"
      echo "path=$RCLONE_PATH" >> "$RCLONE_CONFIG"
      chmod 600 "$RCLONE_CONFIG"
      
      echo "  Rclone configured: $RCLONE_DRIVE:$RCLONE_PATH"
      echo ""
      echo "NOTE: Ensure rclone is configured:"
      echo "  rclone config"
      ;;
      
    rsync)
      if [[ -z "${RSYNC_USER:-}" ]] || [[ -z "${RSYNC_SERVER:-}" ]] || \
         [[ -z "${RSYNC_PATH:-}" ]]; then
        echo "ERROR: Rsync requires RSYNC_USER, RSYNC_SERVER, RSYNC_PATH"
        exit 1
      fi
      
      # Write rsync config
      RSYNC_CONFIG="/root/.teslaCamRsyncConfig"
      echo "user=$RSYNC_USER" > "$RSYNC_CONFIG"
      echo "server=$RSYNC_SERVER" >> "$RSYNC_CONFIG"
      echo "path=$RSYNC_PATH" >> "$RSYNC_CONFIG"
      chmod 600 "$RSYNC_CONFIG"
      
      echo "  Rsync configured: $RSYNC_USER@$RSYNC_SERVER:$RSYNC_PATH"
      ;;
  esac
}

# Configure primary
configure_backend "$PRIMARY_BACKEND" "Primary"
echo ""

# Configure secondary  
configure_backend "$SECONDARY_BACKEND" "Secondary"
echo ""

echo "=================================="
echo "Configuration Complete!"
echo "=================================="
echo ""
echo "Run verify-archive-configuration.sh to verify setup."
