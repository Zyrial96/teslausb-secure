# TeslaUSB Secure

A security-hardened fork of [TeslaUSB](https://github.com/cimryan/teslausb) by cimryan.

This version includes **43 automated security tests** and fixes for **17 security issues** found in the original codebase.

## ⚠️ Security Improvements

### Critical Fixes (Phase 1)

| Issue | Severity | Fix |
|-------|----------|-----|
| Command Injection via `eval` | 🔴 Critical | Replaced with direct function execution |
| Arbitrary Code Execution via `source` | 🔴 Critical | Safe credential parsing with validation |

### High Priority Fixes (Phase 2)

| Issue | Severity | Fix |
|-------|----------|-----|
| Race Conditions | 🟡 High | File locking with `flock` |
| Data Corruption | 🟡 High | Atomic move operations with verification |
| Config Injection | 🟡 High | Safe parsing for rsync/rclone configs |

### Robustness Improvements (Phase 3)

| Feature | Implementation |
|---------|----------------|
| **Signal Handling** | Graceful shutdown on SIGTERM/SIGINT with proper unmounting |
| **Log Sanitization** | Control character filtering to prevent log injection |
| **Exponential Backoff** | Smart retries: 1s → 2s → 4s → 8s → ... → 60s |
| **URL Encoding** | RFC 3986 compliant encoding for GitHub downloads |
| **Configurable DNS** | No more hardcoded Google DNS |

### Additional Fixes

- **Credential Permissions**: All credential files now use `chmod 600` (owner only)
- **Input Validation**: `campercent` bounds checking (1-100), REPO/BRANCH validation
- **Error Handling**: Proper exit codes and error logging throughout

## 🧪 Test Coverage

```
Phase 1.1 (eval removal):        7/7  ✓
Phase 1.2 (source removal):      11/11 ✓
Phase 2 (file locking):          9/9  ✓
Phase 3 (robustness):            16/16 ✓
──────────────────────────────────────
TOTAL:                           43/43 ✓
```

Run tests:
```bash
bash test/test_retry.sh
bash test/test_credential_parsing.sh
bash test/test_file_locking.sh
bash test/test_phase3.sh
```

## 📁 Structure

```
teslausb-secure/
├── run/                          # Runtime scripts
│   ├── archiveloop               # Main daemon (hardened)
│   ├── send-pushover             # Notifications (safe parsing)
│   ├── cifs_archive/             # CIFS/SMB backend
│   ├── rsync_archive/            # rsync/SSH backend
│   └── rclone_archive/           # Cloud storage backend
├── setup/                        # Installation scripts
│   └── pi/
│       ├── configure.sh          # Main installer (URL encoding, validation)
│       └── create-backingfiles.sh
├── test/                         # Automated test suite
│   ├── test_retry.sh
│   ├── test_credential_parsing.sh
│   ├── test_file_locking.sh
│   └── test_phase3.sh
├── README.md                     # This file
└── LICENSE                       # Original license preserved
```

## 🚀 Quick Start

### Prerequisites
- Raspberry Pi Zero W
- Micro SD card (8GB+)
- Tesla with dashcam feature

### Installation

1. **Flash Raspberry Pi OS** (Lite) to SD card
2. **Enable SSH** and **Configure WiFi**
3. **SSH into the Pi** and run:

```bash
# Become root
sudo -i

# Download and run installer
curl -fsSL https://raw.githubusercontent.com/Zyrial96/teslausb-secure/master/setup/pi/configure.sh | bash
```

### Configuration

Set your archive backend:

```bash
# For CIFS/SMB (Windows/Mac/Linux share)
export ARCHIVE_SYSTEM=cifs
export archiveserver=192.168.1.100
export sharename=TeslaCam
export shareuser=tesla
export sharepassword=yourpassword

# For rsync
export ARCHIVE_SYSTEM=rsync
export RSYNC_USER=tesla
export RSYNC_SERVER=192.168.1.100
export RSYNC_PATH=/backups/tesla

# For rclone (cloud)
export ARCHIVE_SYSTEM=rclone
export RCLONE_DRIVE=gdrive
export RCLONE_PATH=TeslaCam
export ARCHIVE_DNS_SERVER=1.1.1.1  # Optional: custom DNS
```

Then run the installer:
```bash
/setup/pi/configure.sh
```

## 🔒 Security Details

### Before vs After

| Attack Vector | Original | TeslaUSB Secure |
|--------------|----------|-----------------|
| `retry "rm -rf /"` | Executes command | Fails safely |
| Malicious credential file | Code execution | Parsed as text only |
| Concurrent archiveloop | Data corruption | Blocked by file lock |
| Terminal escape in filename | Log corruption | Stripped/filtered |
| World-readable credentials | Any user can read | Owner-only (600) |

### Deployment Security

Always backup before deploying:
```bash
# Backup current installation
tar czf /root/teslausb-backup-$(date +%Y%m%d).tar.gz /root/bin/

# Copy new files
cp run/* /root/bin/
chmod 600 /root/.teslaCam*Credentials

# Restart
reboot
```

## 📝 Changelog

### v2.0.0 - Security Hardening Release
- Removed all `eval` calls (command injection prevention)
- Replaced all `source` calls with safe parsing (code execution prevention)
- Added file locking with `flock` (race condition prevention)
- Implemented atomic move operations (data integrity)
- Added signal handlers for graceful shutdown
- Implemented log sanitization (injection prevention)
- Added exponential backoff for retries
- Added URL encoding for GitHub downloads
- Made DNS server configurable
- Added comprehensive test suite (43 tests)

## 🤝 Attribution

This project is a security-hardened fork of [TeslaUSB](https://github.com/cimryan/teslausb) by cimryan.

Original project: https://github.com/cimryan/teslausb

All original functionality is preserved. Security fixes are provided as a community service.

## 📄 License

Same as original TeslaUSB project. See [LICENSE](LICENSE) file.

## ⚠️ Disclaimer

This software is provided as-is. While we've implemented comprehensive security fixes and testing, always:
1. Test in a non-production environment first
2. Maintain backups of your dashcam footage
3. Verify functionality after updates

Use at your own risk.

---

**Made with ⚡ by Zyrial96**
