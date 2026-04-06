#!/bin/bash -eu

FILE_PATH="$1"

# FIX: Secure credential file permissions
echo "drive=$RCLONE_DRIVE" > "$FILE_PATH"
echo "path=$RCLONE_PATH" >> "$FILE_PATH"

# FIX: Set restrictive permissions (owner read/write only)
chmod 600 "$FILE_PATH"
