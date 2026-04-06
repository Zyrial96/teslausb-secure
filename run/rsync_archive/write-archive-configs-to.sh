#!/bin/bash -eu

FILE_PATH="$1"

# FIX: Secure credential file permissions
echo "user=$RSYNC_USER" > "$FILE_PATH"
echo "server=$RSYNC_SERVER" >> "$FILE_PATH"
echo "path=$RSYNC_PATH" >> "$FILE_PATH"

# FIX: Set restrictive permissions (owner read/write only)
chmod 600 "$FILE_PATH"
