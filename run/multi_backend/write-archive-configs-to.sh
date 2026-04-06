#!/bin/bash -eu
#
# Write multi-backend configs to a file (for backup/export)
#

output_file="$1"

if [[ -z "$output_file" ]]; then
  echo "Usage: $0 <output_file>"
  exit 1
fi

echo "Writing multi-backend configuration to $output_file..."

MULTI_BACKEND_CONFIG="/root/.teslaCamMultiBackendConfig"

if [ ! -r "$MULTI_BACKEND_CONFIG" ]; then
  echo "ERROR: Multi-backend config not found"
  exit 1
fi

# Read configuration
PRIMARY_BACKEND=$(grep "^PRIMARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^PRIMARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')
SECONDARY_BACKEND=$(grep "^SECONDARY_BACKEND=" "$MULTI_BACKEND_CONFIG" 2>/dev/null | head -1 | sed 's/^SECONDARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')

cat > "$output_file" << EOF
# TeslaUSB Multi-Backend Configuration Export
# Generated: $(date)

# Backend Selection
export PRIMARY_BACKEND=$PRIMARY_BACKEND
export SECONDARY_BACKEND=$SECONDARY_BACKEND

EOF

# Append individual backend configs
append_backend_config() {
  local backend="$1"
  
  case "$backend" in
    cifs)
      if [ -r "/root/.teslaCamArchiveConfig" ]; then
        echo "# CIFS Configuration" >> "$output_file"
        cat /root/.teslaCamArchiveConfig >> "$output_file"
        echo "" >> "$output_file"
      fi
      ;;
    rclone)
      if [ -r "/root/.teslaCamRcloneConfig" ]; then
        echo "# Rclone Configuration" >> "$output_file"
        cat /root/.teslaCamRcloneConfig >> "$output_file"
        echo "" >> "$output_file"
      fi
      ;;
    rsync)
      if [ -r "/root/.teslaCamRsyncConfig" ]; then
        echo "# Rsync Configuration" >> "$output_file"
        cat /root/.teslaCamRsyncConfig >> "$output_file"
        echo "" >> "$output_file"
      fi
      ;;
  esac
}

append_backend_config "$PRIMARY_BACKEND"
append_backend_config "$SECONDARY_BACKEND"

chmod 600 "$output_file"
echo "Configuration exported to: $output_file"
