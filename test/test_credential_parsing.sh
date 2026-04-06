#!/bin/bash
# Unit Tests for safe credential parsing (Phase 1.2)
# Run: bash test_credential_parsing.sh

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

function assert_not_empty() {
  local value="$1"
  local msg="${2:-}"
  
  if [[ -n "$value" ]]; then
    echo "✓ PASS: $msg"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo "✗ FAIL: $msg (value is empty)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

function assert_empty() {
  local value="$1"
  local msg="${2:-}"
  
  if [[ -z "$value" ]]; then
    echo "✓ PASS: $msg"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    return 0
  else
    echo "✗ FAIL: $msg (value should be empty but is: $value)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
}

# Create temp directory for test files
TEST_DIR=$(mktemp -d)
trap "rm -rf $TEST_DIR" EXIT

# Test 1: Normal credentials
echo "--- Test 1: Normal credentials ---"
cat > "$TEST_DIR/creds1" << 'EOF'
export pushover_enabled=true
export pushover_user_key=u123456789
export pushover_app_key=a987654321
EOF

user_key=$(grep "^export pushover_user_key=" "$TEST_DIR/creds1" 2>/dev/null | sed "s/^export pushover_user_key=//; s/^[\\'\"]//; s/[\\'\"]$//")
app_key=$(grep "^export pushover_app_key=" "$TEST_DIR/creds1" 2>/dev/null | sed "s/^export pushover_app_key=//; s/^[\\'\"]//; s/[\\'\"]$//")

assert_equals "u123456789" "$user_key" "User key parsed correctly" || true
assert_equals "a987654321" "$app_key" "App key parsed correctly" || true

# Test 2: Credentials with quotes
echo "--- Test 2: Credentials with quotes ---"
cat > "$TEST_DIR/creds2" << 'EOF'
export pushover_user_key="quoted_user_key"
export pushover_app_key='quoted_app_key'
EOF

user_key=$(grep "^export pushover_user_key=" "$TEST_DIR/creds2" 2>/dev/null | sed "s/^export pushover_user_key=//; s/^[\\'\"]//; s/[\\'\"]$//")
app_key=$(grep "^export pushover_app_key=" "$TEST_DIR/creds2" 2>/dev/null | sed "s/^export pushover_app_key=//; s/^[\\'\"]//; s/[\\'\"]$//")

assert_equals "quoted_user_key" "$user_key" "Quoted user key parsed correctly" || true
assert_equals "quoted_app_key" "$app_key" "Quoted app key parsed correctly" || true

# Test 3: Missing credentials file
echo "--- Test 3: Missing credentials file ---"
user_key=$(grep "^export pushover_user_key=" "$TEST_DIR/nonexistent" 2>/dev/null | sed "s/^export pushover_user_key=//")
assert_empty "$user_key" "Missing file returns empty user key" || true

# Test 4: Malicious credential file (simulated injection attempt)
echo "--- Test 4: Malicious credential file (safe parsing) ---"
cat > "$TEST_DIR/creds_malicious" << 'EOF'
export pushover_user_key=$(echo INJECTED)
export pushover_app_key=a123
EOF

# With 'source', this would execute 'echo INJECTED'
# With grep/sed, it's treated as literal string
user_key=$(grep "^export pushover_user_key=" "$TEST_DIR/creds_malicious" 2>/dev/null | sed "s/^export pushover_user_key=//; s/^[\\'\"]//; s/[\\'\"]$//")

# The key should be the literal string '$(echo INJECTED)', not executed
if [[ "$user_key" == *"INJECTED"* ]] && [[ "$user_key" == *"echo"* ]]; then
  echo "✓ PASS: Malicious content not executed (parsed as literal)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Malicious content may have been processed unexpectedly"
  echo "  Parsed value: $user_key"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: Credential with spaces (trimmed)
echo "--- Test 5: Credentials with leading/trailing spaces ---"
cat > "$TEST_DIR/creds_spaces" << 'EOF'
export pushover_user_key=  spaced_user_key  
export pushover_app_key=	tabbed_key	
EOF

user_key=$(grep "^export pushover_user_key=" "$TEST_DIR/creds_spaces" 2>/dev/null | sed "s/^export pushover_user_key=//; s/^[\\'\"]//; s/[\\'\"]$//; s/^[[:space:]]*//; s/[[:space:]]*$//")
app_key=$(grep "^export pushover_app_key=" "$TEST_DIR/creds_spaces" 2>/dev/null | sed "s/^export pushover_app_key=//; s/^[\\'\"]//; s/[\\'\"]$//; s/^[[:space:]]*//; s/[[:space:]]*$//")

assert_equals "spaced_user_key" "$user_key" "Spaces trimmed from user key" || true
assert_equals "tabbed_key" "$app_key" "Tabs trimmed from app key" || true

# Test 6: Injection character detection
echo "--- Test 6: Injection character detection ---"
malicious_key='user; rm -rf /'
if [[ "$malicious_key" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
  echo "✓ PASS: Injection characters detected in: $malicious_key"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Injection characters not detected"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Valid key passes validation
echo "--- Test 7: Valid key passes validation ---"
valid_key='abc123XYZ_valid-key'
if [[ "$valid_key" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
  echo "✗ FAIL: Valid key flagged as malicious"
  TESTS_FAILED=$((TESTS_FAILED + 1))
else
  echo "✓ PASS: Valid key passes injection check"
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# Test 8: Backtick injection attempt
echo "--- Test 8: Backtick injection detection ---"
backtick_key='user`whoami`'
if [[ "$backtick_key" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
  echo "✓ PASS: Backtick injection detected"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  echo "✗ FAIL: Backtick injection not detected"
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
