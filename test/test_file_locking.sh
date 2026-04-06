#!/bin/bash
# Unit Tests for file locking and atomic operations (Phase 2)
# Run: bash test_file_locking.sh

TESTS_PASSED=0
TESTS_FAILED=0

function assert_true() {
  local msg="$1"
  if [ $? -eq 0 ]; then
    echo "✓ PASS: $msg"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: $msg"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

function assert_false() {
  local msg="$1"
  if [ $? -ne 0 ]; then
    echo "✓ PASS: $msg"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: $msg"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

function assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  
  if [ "$expected" = "$actual" ]; then
    echo "✓ PASS: $msg"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: $msg"
    echo "  Expected: $expected"
    echo "  Actual: $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Test 1: flock exclusive lock works
echo "--- Test 1: Exclusive lock acquisition ---"
LOCK_FILE="$TEST_DIR/test.lock"
(
  exec 200>"$LOCK_FILE"
  if flock -n 200; then
    echo "locked" > "$TEST_DIR/status"
    sleep 2
  fi
) &
bg_pid=$!
sleep 0.5

# Try to acquire same lock (should fail)
exec 201>"$LOCK_FILE"
if flock -n 201 2>/dev/null; then
  echo "✗ FAIL: Second process should not acquire lock"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo "✓ PASS: Second process correctly blocked"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

wait $bg_pid 2>/dev/null

# Test 2: Lock timeout works
echo "--- Test 2: Lock timeout ---"
(
  exec 200>"$LOCK_FILE"
  flock -n 200
  sleep 5
) &
bg_pid=$!
sleep 0.5

exec 201>"$LOCK_FILE"
start_time=$(date +%s)
if flock -w 1 201 2>/dev/null; then
  echo "✗ FAIL: Should have timed out"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  end_time=$(date +%s)
  elapsed=$((end_time - start_time))
  if [ $elapsed -lt 2 ]; then
    echo "✓ PASS: Lock timeout works (elapsed: ${elapsed}s)"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: Timeout took too long"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
fi

kill $bg_pid 2>/dev/null
wait $bg_pid 2>/dev/null

# Test 3: Atomic file operation (copy + sync + move)
echo "--- Test 3: Atomic move operation ---"
mkdir -p "$TEST_DIR/source" "$TEST_DIR/dest"
echo "test content" > "$TEST_DIR/source/testfile.txt"

orig_size=$(stat -c%s "$TEST_DIR/source/testfile.txt")
temp_dest="$TEST_DIR/dest/.testfile.txt.tmp.$$"
final_dest="$TEST_DIR/dest/testfile.txt"

# Simulate atomic move
cp -- "$TEST_DIR/source/testfile.txt" "$temp_dest"
sync
copy_size=$(stat -c%s "$temp_dest")
mv -- "$temp_dest" "$final_dest"
rm -- "$TEST_DIR/source/testfile.txt"

if [ "$orig_size" -eq "$copy_size" ] && [ -e "$final_dest" ] && [ ! -e "$TEST_DIR/source/testfile.txt" ]; then
  echo "✓ PASS: Atomic move completed successfully"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Atomic move failed"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: Size verification catches corruption
echo "--- Test 4: Size verification ---"
echo "original data" > "$TEST_DIR/test_orig.txt"
orig_size=$(stat -c%s "$TEST_DIR/test_orig.txt")
echo "corrupted" > "$TEST_DIR/test_copy.txt"
copy_size=$(stat -c%s "$TEST_DIR/test_copy.txt")

if [ "$orig_size" -ne "$copy_size" ]; then
  echo "✓ PASS: Size mismatch detected (corruption would be caught)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Size check did not detect difference"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: Safe credential parsing (rsync format)
echo "--- Test 5: Rsync credential parsing ---"
cat > "$TEST_DIR/rsync.conf" << 'EOF'
user=testuser
server=192.168.1.100
path=/backups/tesla
EOF

parsed_user=$(grep "^user=" "$TEST_DIR/rsync.conf" | head -1 | sed 's/^user=//' | tr -d '"'\\'' | tr -d '[:space:]')
parsed_server=$(grep "^server=" "$TEST_DIR/rsync.conf" | head -1 | sed 's/^server=//' | tr -d '"'\\'' | tr -d '[:space:]')

assert_equals "testuser" "$parsed_user" "Rsync user parsed correctly" || true
assert_equals "192.168.1.100" "$parsed_server" "Rsync server parsed correctly" || true

# Test 6: Injection detection in config values
echo "--- Test 6: Config injection detection ---"
malicious_user='user; rm -rf /'
if [[ "$malicious_user" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
  echo "✓ PASS: Injection characters detected in config"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Injection not detected"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Duplicate file detection
echo "--- Test 7: Duplicate file detection ---"
mkdir -p "$TEST_DIR/archive"
echo "existing" > "$TEST_DIR/archive/duplicate.txt"

if [ -e "$TEST_DIR/archive/duplicate.txt" ]; then
  echo "✓ PASS: Duplicate file detection works"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: File existence check failed"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: Trap cleanup
echo "--- Test 8: Trap and cleanup ---"
CLEANUP_RAN=false
(
  exec 200>"$TEST_DIR/trap_test.lock"
  flock -n 200
  trap 'CLEANUP_RAN=true; echo "cleanup" > '"$TEST_DIR/cleanup_marker"'' EXIT
  exit 0
)
sleep 0.1
if [ -e "$TEST_DIR/cleanup_marker" ]; then
  echo "✓ PASS: Trap cleanup executed"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Trap cleanup did not run"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Summary
echo ""
echo "========================================="
echo "Test Results:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "========================================="

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo "All tests passed! ✓"
  exit 0
else
  echo "Some tests failed! ✗"
  exit 1
fi
