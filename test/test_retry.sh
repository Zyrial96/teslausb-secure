#!/bin/bash
# Unit Tests for eval-free retry function
# Run: bash test_retry.sh

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

# Import the retry function (mock log function)
function log() { :; }

function retry () {
  local cmd="$1"
  shift
  local attempts=0
  
  while true; do
    if "$cmd" "$@"; then
      return 0
    fi
    
    if [ "$attempts" -ge 10 ]; then
      return 1
    fi
    
    attempts=$((attempts + 1))
  done
}

# Test 1: Success on first try
echo "--- Test 1: Success on first try ---"
COUNTER=0
success_first_try() {
  COUNTER=$((COUNTER + 1))
  return 0
}
retry success_first_try
assert_equals 1 "$COUNTER" "Command should be called exactly once" || true

# Test 2: Success on third try
echo "--- Test 2: Success on third try ---"
COUNTER=0
success_third_try() {
  COUNTER=$((COUNTER + 1))
  if [ "$COUNTER" -lt 3 ]; then
    return 1
  fi
  return 0
}
retry success_third_try
assert_equals 3 "$COUNTER" "Command should be called 3 times" || true

# Test 3: Exhaust all retries (should return 1/false)
echo "--- Test 3: Exhaust all retries ---"
COUNTER=0
always_fail() {
  COUNTER=$((COUNTER + 1))
  return 1
}

retry_result=0
retry always_fail || retry_result=1

if [ "$retry_result" -eq 1 ]; then
  echo "✓ PASS: retry correctly returns failure when exhausted"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: retry should return failure when exhausted"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi
assert_equals 11 "$COUNTER" "Command should be called 11 times (initial + 10 retries)" || true

# Test 4: Command with arguments
echo "--- Test 4: Command with arguments ---"
RECEIVED_ARGS=""
cmd_with_args() {
  RECEIVED_ARGS="$1|$2|$3"
  return 0
}
retry cmd_with_args "arg1" "arg2" "arg3"
assert_equals "arg1|arg2|arg3" "$RECEIVED_ARGS" "Arguments should be passed correctly" || true

# Test 5: Security - Command injection attempt should fail safely
echo "--- Test 5: Security - No command injection ---"
# With eval, 'echo pwned' would execute 'pwned'
# Without eval, it looks for a command literally named 'echo pwned' which doesn't exist
injection_result=0
retry "echo INJECTED" 2>/dev/null || injection_result=1

if [ "$injection_result" -eq 1 ]; then
  echo "✓ PASS: Command injection prevented (no eval)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Command injection should have been prevented"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Function scope - can call functions defined in same file
echo "--- Test 6: Function calls work correctly ---"
helper_var=""
helper_function() {
  helper_var="called with $1"
  return 0
}
retry helper_function "test_arg"
assert_equals "called with test_arg" "$helper_var" "Function calls with arguments should work" || true

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
