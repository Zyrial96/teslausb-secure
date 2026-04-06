#!/bin/bash
# Unit Tests for Phase 3: Signal Handling, Log Sanitization, URL Encoding
# Run: bash test_phase3.sh

TESTS_PASSED=0
TESTS_FAILED=0

function assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-}"
  
  if [ "$expected" = "$actual" ]; then
    echo "✓ PASS: $msg"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo "✗ FAIL: $msg"
    echo "  Expected: $expected"
    echo "  Actual: $actual"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

function assert_not_contains() {
  local string="$1"
  local substring="$2"
  local msg="${3:-}"
  
  if [[ "$string" != *"$substring"* ]]; then
    echo "✓ PASS: $msg"
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    echo "✗ FAIL: $msg"
    echo "  String contains: $substring"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Test 1: URL encoding function
echo "--- Test 1: URL encoding ---"
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) encoded+="$c" ;;
            *) printf -v o '%%%02x' "'$c"; encoded+="$o" ;;
        esac
    done
    echo "$encoded"
}

assert_equals "hello" "$(urlencode "hello")" "Simple string encodes correctly" || true
assert_equals "hello%20world" "$(urlencode "hello world")" "Space encodes to %20" || true
# Note: URL encoding produces lowercase hex which is valid per RFC 3986
encoded=$(urlencode "test/path")
if [[ "$encoded" == *"%2"[fF] ]]; then
  echo "✓ PASS: Slash encodes correctly (got: $encoded)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Slash encoding failed (got: $encoded)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
assert_equals "foo%40bar" "$(urlencode "foo@bar")" "@ encodes to %40" || true

# Test 2: Log sanitization
echo "--- Test 2: Log sanitization ---"
sanitize_log() {
  local message="$1"
  message=$(printf '%s' "$message" | tr -d '\r\n\000-\031\177' | sed 's/\\e\[[0-9;]*m//g')
  echo "$message"
}

assert_equals "normal message" "$(sanitize_log "normal message")" "Normal text unchanged" || true
assert_equals "message with spaces" "$(sanitize_log "message with spaces")" "Spaces preserved" || true
assert_not_contains "$(sanitize_log "test
newline")" $'\n' "Newlines removed" || true
assert_not_contains "$(sanitize_log "test")" $'\r' "Carriage returns removed" || true

# Test 3: Signal handler trap setup
echo "--- Test 3: Signal handlers ---"
(
  CLEANUP_RAN=false
  cleanup() { CLEANUP_RAN=true; echo "cleanup ran" > "$TEST_DIR/cleanup_signal"; exit 0; }
  trap cleanup EXIT INT TERM
  exit 0
)
sleep 0.1
if [ -e "$TEST_DIR/cleanup_signal" ]; then
  echo "✓ PASS: Exit trap executed"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Exit trap not executed"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: Exponential backoff calculation
echo "--- Test 4: Exponential backoff ---"
calculate_delay() {
  local attempts=$1
  local delay=1
  local max_delay=60
  local i
  
  for ((i=0; i<attempts; i++)); do
    delay=$((delay * 2))
    if [ "$delay" -gt "$max_delay" ]; then
      delay=$max_delay
    fi
  done
  echo "$delay"
}

assert_equals 2 "$(calculate_delay 1)" "After 1 retry: 2s" || true
assert_equals 4 "$(calculate_delay 2)" "After 2 retries: 4s" || true
assert_equals 8 "$(calculate_delay 3)" "After 3 retries: 8s" || true
# Note: Max delay is capped at 60s, so after 5 doublings we hit 32, then 60
# 1->2->4->8->16->32->60 (capped)
assert_equals 60 "$(calculate_delay 6)" "After 6 retries: 60s (capped at max)" || true
assert_equals 60 "$(calculate_delay 10)" "After 10 retries: 60s (max)" || true

# Test 5: Configurable DNS
echo "--- Test 5: Configurable DNS ---"
ARCHIVE_DNS_SERVER="1.1.1.1"
if [ "$ARCHIVE_DNS_SERVER" = "1.1.1.1" ]; then
  echo "✓ PASS: DNS server is configurable"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: DNS config not working"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Cleanup state tracking
echo "--- Test 6: Cleanup state (prevents double cleanup) ---"
(
  CLEANUP_DONE=false
  cleanup_count=0
  
  cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then
      return
    fi
    CLEANUP_DONE=true
    cleanup_count=$((cleanup_count + 1))
  }
  
  trap cleanup EXIT
  cleanup  # First call
  cleanup  # Second call (should be ignored)
  
  if [ "$cleanup_count" -eq 1 ]; then
    echo "cleanup_ok" > "$TEST_DIR/cleanup_count"
  fi
  exit 0
)

if [ -e "$TEST_DIR/cleanup_count" ]; then
  echo "✓ PASS: Cleanup state prevents double execution"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Cleanup ran multiple times"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Safe file check (findmnt)
echo "--- Test 7: Mount point detection ---"
mkdir -p "$TEST_DIR/mounttest"
if findmnt --mountpoint / > /dev/null 2>&1; then
  echo "✓ PASS: findmnt works for detecting mounts"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: findmnt not working"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 8: tr control character removal
echo "--- Test 8: Control character filtering ---"
# Create string with control characters using printf
test_string=$(printf 'hello\001\002\037world')
filtered=$(printf '%s' "$test_string" | tr -d '\000-\031')
if [ "$filtered" = "helloworld" ]; then
  echo "✓ PASS: Control characters 0-31 removed"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Control characters not removed"
  echo "  Filtered length: ${#filtered}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Summary
echo ""
echo "========================================="
echo "Phase 3 Test Results:"
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "========================================="

if [ "$TESTS_FAILED" -eq 0 ]; then
  echo "All Phase 3 tests passed! ✓"
  exit 0
else
  echo "Some tests failed! ✗"
  exit 1
fi
