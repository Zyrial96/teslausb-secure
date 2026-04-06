---
name: teslausb-secure
description: Security-hardened TeslaUSB with 50 automated tests and 17 security fixes. Raspberry Pi Zero W dashcam recorder for Tesla vehicles with enterprise-grade hardening. Features multi-backend support for simultaneous archiving to NAS + Cloud.
read_when:
  - Setting up TeslaUSB for the first time
  - Hardening existing TeslaUSB installation
  - Deploying secure dashcam archiving
  - Need multi-backend archive support (CIFS/rsync/rclone)
  - Setting up NAS + Cloud backup simultaneously
metadata:
  clawdbot:
    emoji: 🚗
    requires:
      bins: [bash, curl, modprobe]
      hardware: [raspberry-pi-zero-w]
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# TeslaUSB Secure

A security-hardened fork of TeslaUSB with 43 automated tests and fixes for 17 security vulnerabilities.

## Quick Install

```bash
# One-line installer
curl -fsSL https://raw.githubusercontent.com/Zyrial96/teslausb-secure/main/setup/pi/configure.sh | sudo bash
```

## Security Features

- ✅ Command injection prevention (eval removed)
- ✅ Code execution prevention (source replaced with safe parsing)
- ✅ File locking (flock) for race condition prevention
- ✅ Atomic move operations with verification
- ✅ Signal handling for graceful shutdown
- ✅ Log sanitization (injection prevention)
- ✅ Exponential backoff for retries
- ✅ URL encoding for GitHub downloads
- ✅ Configurable DNS server
- ✅ Credential file permissions (600)
- ✅ Input validation (campercent, REPO/BRANCH)

## Smart Retention Policy 🆕

Automatisches Management der lokalen Speicherung mit intelligenter Aufbewahrung:

- **Lokal behalten:** Clips der letzten 7 Tage (konfigurierbar)
- **Automatisch archivieren:** Ältere Clips werden ins Archiv verschoben
- **Löschung nach Upload:** Lokale Kopien werden nach erfolgreichem Upload entfernt

### Konfiguration

```bash
# Retention-Dauer in Tagen (Default: 7)
export RETENTION_DAYS=7

# Beispiele:
export RETENTION_DAYS=3   # Nur 3 Tage lokal behalten
export RETENTION_DAYS=14  # 2 Wochen lokal behalten
export RETENTION_DAYS=30  # 1 Monat lokal behalten
```

Die Variable `RETENTION_DAYS` kann in der TeslaUSB-Konfiguration gesetzt werden und gilt für alle Archive-Backends (CIFS, rsync, rclone).

## Test Coverage

```
Phase 1.1 (eval removal):        7/7  ✓
Phase 1.2 (source removal):      11/11 ✓
Phase 2 (file locking):          9/9  ✓
Phase 3 (robustness):            16/16 ✓
Phase 4 (multi-backend):         7/7  ✓
────────────────────────────────────────
TOTAL:                           50/50 ✓
```

## Notifications

TeslaUSB unterstützt zwei Benachrichtigungssysteme:

| Feature | Pushover | Discord |
|---------|----------|---------|
| **Preis** | Kostenpflichtig (5$/Monat) | Kostenlos |
| **Format** | Einfache Nachricht | Rich Embeds |
| **Speicher-Info** | ❌ Nein | ✅ Ja |
| **Fehler-Tracking** | ❌ Nein | ✅ Ja |
| **Rate-Limiting** | ❌ Nein | ✅ Ja |
| **Setup** | API-Key + User-Key | Webhook URL |

Beide Systeme können parallel genutzt werden – das System sendet automatisch an beide, falls konfiguriert.

## Configuration

### CIFS/SMB (NAS)
```bash
export ARCHIVE_SYSTEM=cifs
export archiveserver=192.168.1.100
export sharename=TeslaCam
export shareuser=tesla
export sharepassword=yourpassword
export RETENTION_DAYS=7
./setup/pi/configure.sh
```

### rsync (SSH)
```bash
export ARCHIVE_SYSTEM=rsync
export RSYNC_USER=tesla
export RSYNC_SERVER=192.168.1.100
export RSYNC_PATH=/backups/tesla
export RETENTION_DAYS=7
./setup/pi/configure.sh
```

### rclone (Cloud)
```bash
export ARCHIVE_SYSTEM=rclone
export RCLONE_DRIVE=gdrive
export RCLONE_PATH=TeslaCam
export ARCHIVE_DNS_SERVER=1.1.1.1
export RETENTION_DAYS=7
./setup/pi/configure.sh
```

### Multi-Backend (Primary + Secondary) 🆕
Archive simultaneously to CIFS (local NAS) AND rclone (cloud backup). Both backends must succeed for "complete" status.

```bash
# Set backend types
export ARCHIVE_SYSTEM=multi
export PRIMARY_BACKEND=cifs
export SECONDARY_BACKEND=rclone

# Primary backend (CIFS/SMB)
export archiveserver=192.168.1.100
export sharename=TeslaCam
export shareuser=tesla
export sharepassword=yourpassword

# Secondary backend (rclone cloud)
export RCLONE_DRIVE=gdrive
export RCLONE_PATH=TeslaCam/Backup

# Configure
./setup/pi/configure.sh
```

**Supported Backend Combinations:**
| Primary | Secondary | Use Case |
|---------|-----------|----------|
| cifs | rclone | NAS + Cloud Backup |
| cifs | rsync | NAS + Remote Server |
| rsync | rclone | Remote Server + Cloud |
| rclone | rsync | Cloud + Remote Server |

**Behavior:**
- Files are archived to PRIMARY first
- Only successfully archived files go to SECONDARY
- Source files are deleted ONLY if BOTH backends succeed
- `/tmp/archive_complete` created on full success
- `/tmp/archive_partial` created if only primary succeeds

## File Structure

```
teslausb-secure/
├── run/
│   ├── archiveloop              # Main daemon (hardened)
│   ├── send-pushover            # Pushover notifications (safe parsing)
│   ├── send-discord             # Discord webhook notifications
│   ├── cifs_archive/            # CIFS/SMB backend
│   ├── rsync_archive/           # rsync/SSH backend
│   ├── rclone_archive/          # Cloud storage backend
│   └── multi_backend/           # Multi-backend support (primary + secondary)
│       ├── archive-clips.sh     # Simultaneous dual-backend archiving
│       ├── verify-archive-configuration.sh
│       ├── configure-archive.sh
│       ├── connect-archive.sh
│       ├── disconnect-archive.sh
│       ├── archive-is-reachable.sh
│       └── write-archive-configs-to.sh
├── setup/pi/
│   ├── configure.sh             # Main installer
│   └── create-backingfiles.sh   # SD card setup
├── dashboard/                   # Health monitoring dashboard
│   ├── teslausb-dashboard.py    # HTTP server
│   ├── index.html               # Dashboard UI
│   └── teslausb-dashboard.service # systemd unit
└── test/                        # 43 automated tests
```

## Deployment

1. **Backup current installation:**
   ```bash
   tar czf /root/teslausb-backup-$(date +%Y%m%d).tar.gz /root/bin/
   ```

2. **Copy fixed files:**
   ```bash
   cp run/* /root/bin/
   chmod 600 /root/.teslaCam*Credentials
   ```

3. **Restart:**
   ```bash
   reboot
   ```

## Discord Notifications

TeslaUSB unterstützt Discord-Webhooks als Alternative zu Pushover für Echtzeit-Benachrichtigungen.

### Discord Einrichtung

#### 1. Webhook erstellen

1. Öffne deinen Discord-Server
2. Gehe zu **Servereinstellungen** → **Integrationen** → **Webhooks**
3. Klicke auf **Neuer Webhook**
4. Wähle den Kanal für Benachrichtigungen
5. Kopiere die **Webhook-URL** (sieht aus wie: `https://discord.com/api/webhooks/123456789/abcdefghijklmnopqrstuvwxyz`)

#### 2. Credentials konfigurieren

Erstelle die Credentials-Datei auf dem Raspberry Pi:

```bash
# Erstelle Credentials-Datei
cat > /root/.teslaCamDiscordCredentials << 'EOF'
export discord_webhook_url="https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"
export discord_username="TeslaUSB"
export discord_avatar_url="https://raw.githubusercontent.com/marcone/teslausb/main/teslausb-logo.png"
EOF

# Setze Berechtigungen (nur root lesbar)
chmod 600 /root/.teslaCamDiscordCredentials
```

#### 3. Script installieren

```bash
# Kopiere das Discord-Script
cp run/send-discord /root/bin/send-discord
chmod +x /root/bin/send-discord
```

### Discord Embed-Format

Benachrichtigungen werden als schöne Discord Embeds gesendet:

🚗 **TeslaUSB - Archivierung abgeschlossen**
- 📹 Anzahl der archivierten Dateien
- ⚠️ Anzahl fehlgeschlagener Dateien (falls vorhanden)
- 💾 Speicherplatz-Informationen (optional)
- Zeitstempel und Footer mit Hostname

### Rate-Limiting

Das Script implementiert sicheres Rate-Limiting:
- **Lokal**: Mindestens 2 Sekunden zwischen Requests
- **Discord API**: Respektiert `Retry-After` Header
- Automatische Wartezeit bei 429 Too Many Requests

### Sicherheitsfeatures

- ✅ Safe credential parsing (kein `source` oder `eval`)
- ✅ URL-Validierung (nur gültige Discord-Webhook-URLs)
- ✅ Injection-Schutz (keine Sonderzeichen in URLs)
- ✅ Input-Sanitization für alle Benutzereingaben

## Health Monitoring Dashboard

Web-based dashboard for real-time TeslaUSB status monitoring.

### Features
- 📊 SD-Karten-Nutzung (Root & CAM Partitionen)
- ☁️ Archiv-Speicher-Status
- 📡 WiFi-Verbindung (SSID, Signal, IP)
- 📁 Anzahl Aufnahmen (Recent/Saved/Sentry Clips)
- 📤 Letztes Archiv + Gesamt archivierte Dateien
- ⚠️ Fehler-Log (letzte 10 Einträge)
- 🖥️ System-Info (Uptime, Temperatur)

### Installation auf dem Pi

```bash
# 1. Dashboard-Verzeichnis erstellen
sudo mkdir -p /opt/teslausb-dashboard

# 2. Dashboard-Dateien kopieren (vom Repo)
sudo cp dashboard/teslausb-dashboard.py /opt/teslausb-dashboard/
sudo cp dashboard/index.html /opt/teslausb-dashboard/
sudo chmod +x /opt/teslausb-dashboard/teslausb-dashboard.py

# 3. Systemd Service installieren
sudo cp dashboard/teslausb-dashboard.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable teslausb-dashboard
sudo systemctl start teslausb-dashboard

# 4. Firewall-Regel (falls aktiviert)
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
```

### Zugriff
- **URL:** `http://<pi-ip>/`
- **API:** `http://<pi-ip>/api/status` (JSON)
- **Auto-Refresh:** Alle 30 Sekunden

### Troubleshooting
```bash
# Status prüfen
sudo systemctl status teslausb-dashboard

# Logs ansehen
sudo journalctl -u teslausb-dashboard -f

# Neustart
sudo systemctl restart teslausb-dashboard
```

## GitHub Repository

https://github.com/Zyrial96/teslausb-secure

## Testing

Run all tests:
```bash
bash test/test_retry.sh
bash test/test_credential_parsing.sh
bash test/test_file_locking.sh
bash test/test_phase3.sh
bash test/test_discord.sh
bash test/test_multi_backend.sh  # New: Multi-backend tests
```

### Discord Notification Tests

Das Discord-Test-Suite umfasst 8 Tests:
- **Credential Parsing**: Sicheres Parsen ohne Code-Ausführung
- **Injection Prevention**: Erkennung bösartiger Eingaben
- **URL Validation**: Format-Validierung für Webhook-URLs
- **Embed Generation**: Korrekte JSON-Struktur
- **Rate Limiting**: Lokale und API-Rate-Limits
- **Color Selection**: Status-basierte Farbcodierung
- **Log Sanitization**: Bereinigung von Log-Nachrichten
