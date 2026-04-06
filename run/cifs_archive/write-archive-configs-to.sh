#!/bin/bash -eu

FILE_PATH="$1"

# FIX: Secure credential file permissions
echo "username=$shareuser" > "$FILE_PATH"
echo "password=$sharepassword" >> "$FILE_PATH"

# FIX: Set restrictive permissions (owner read/write only)
chmod 600 "$FILE_PATH"
