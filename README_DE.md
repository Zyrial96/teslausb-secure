# TeslaUSB Secure

Ein sicherheitsgehärteter Fork von [TeslaUSB](https://github.com/cimryan/teslausb) von cimryan.

Diese Version enthält **43 automatisierte Sicherheitstests** und Fixes für **17 Sicherheitsprobleme**, die im Original-Code gefunden wurden.

## ⚠️ Sicherheitsverbesserungen

### Kritische Fixes (Phase 1)

| Problem | Schwere | Lösung |
|---------|---------|--------|
| Command Injection via `eval` | 🔴 Kritisch | Ersetzt durch direkte Funktionsausführung |
| Code-Ausführung via `source` | 🔴 Kritisch | Sicheres Credential-Parsing mit Validierung |

### Hochpriorisierte Fixes (Phase 2)

| Problem | Schwere | Lösung |
|---------|---------|--------|
| Race Conditions | 🟡 Hoch | File Locking mit `flock` |
| Datenkorruption | 🟡 Hoch | Atomare Verschiebe-Operationen mit Verifikation |
| Config Injection | 🟡 Hoch | Sicheres Parsing für rsync/rclone Configs |

### Robustheit-Verbesserungen (Phase 3)

| Feature | Implementierung |
|---------|-----------------|
| **Signal-Handling** | Graceful Shutdown bei SIGTERM/SIGINT mit sauberem Unmount |
| **Log-Sanitisierung** | Kontrollzeichen-Filterung zur Verhinderung von Log-Injection |
| **Exponentieller Backoff** | Intelligente Retries: 1s → 2s → 4s → 8s → ... → 60s |
| **URL-Encoding** | RFC 3986 konformes Encoding für GitHub-Downloads |
| **Konfigurierbarer DNS** | Kein hardcodierter Google DNS mehr |

### Zusätzliche Fixes

- **Credential-Berechtigungen**: Alle Credential-Dateien nutzen jetzt `chmod 600` (nur Owner)
- **Input-Validierung**: `campercent` Bounds-Checking (1-100), REPO/BRANCH Validierung
- **Error-Handling**: Korrekte Exit-Codes und Error-Logging durchgängig

## 🧪 Test-Abdeckung

```
Phase 1.1 (eval-Entfernung):    7/7  ✓
Phase 1.2 (source-Entfernung):  11/11 ✓
Phase 2 (File Locking):         9/9  ✓
Phase 3 (Robustheit):           16/16 ✓
────────────────────────────────────────
GESAMT:                         43/43 ✓
```

Tests ausführen:
```bash
bash test/test_retry.sh
bash test/test_credential_parsing.sh
bash test/test_file_locking.sh
bash test/test_phase3.sh
```

## 📁 Struktur

```
teslausb-secure/
├── run/                          # Runtime-Skripte
│   ├── archiveloop               # Main Daemon (gehärtet)
│   ├── send-pushover             # Benachrichtigungen (sicheres Parsing)
│   ├── cifs_archive/             # CIFS/SMB Backend
│   ├── rsync_archive/            # rsync/SSH Backend
│   └── rclone_archive/           # Cloud Storage Backend
├── setup/                        # Installationsskripte
│   └── pi/
│       ├── configure.sh          # Main Installer (URL-Encoding, Validierung)
│       └── create-backingfiles.sh
├── test/                         # Automatisierte Test-Suite
│   ├── test_retry.sh
│   ├── test_credential_parsing.sh
│   ├── test_file_locking.sh
│   └── test_phase3.sh
├── README.md                     # Diese Datei
└── LICENSE                       # Originale Lizenz beibehalten
```

## 🚀 Schnellstart

### Voraussetzungen
- Raspberry Pi Zero W
- Micro SD-Karte (8GB+)
- Tesla mit Dashcam-Funktion

### Installation

1. **Raspberry Pi OS flashen** (Lite) auf SD-Karte
2. **SSH aktivieren** und **WiFi konfigurieren**
3. **Per SSH auf den Pi verbinden** und ausführen:

```bash
# Root werden
sudo -i

# Installer herunterladen und ausführen
curl -fsSL https://raw.githubusercontent.com/Zyrial96/teslausb-secure/main/setup/pi/configure.sh | bash
```

### Konfiguration

Archive-Backend festlegen:

```bash
# Für CIFS/SMB (Windows/Mac/Linux Share)
export ARCHIVE_SYSTEM=cifs
export archiveserver=192.168.1.100
export sharename=TeslaCam
export shareuser=tesla
export sharepassword=deinpasswort

# Für rsync
export ARCHIVE_SYSTEM=rsync
export RSYNC_USER=tesla
export RSYNC_SERVER=192.168.1.100
export RSYNC_PATH=/backups/tesla

# Für rclone (Cloud)
export ARCHIVE_SYSTEM=rclone
export RCLONE_DRIVE=gdrive
export RCLONE_PATH=TeslaCam
export ARCHIVE_DNS_SERVER=1.1.1.1  # Optional: eigener DNS
```

Dann Installer ausführen:
```bash
/setup/pi/configure.sh
```

## 🔒 Sicherheitsdetails

### Vorher vs Nachher

| Angriffsvektor | Original | TeslaUSB Secure |
|---------------|----------|-----------------|
| `retry "rm -rf /"` | Führt Befehl aus | Schlägt sicher fehl |
| Bösartige Credential-Datei | Code-Ausführung | Wird nur als Text geparst |
| Gleichzeitiger archiveloop | Datenkorruption | Durch File Lock blockiert |
| Terminal-Escapes im Dateinamen | Log-Korruption | Werden gefiltert/gestrippt |
| World-readable Credentials | Jeder User kann lesen | Nur Owner (600) |

### Deployment-Sicherheit

Vor dem Deployment immer Backup erstellen:
```bash
# Backup aktueller Installation
tar czf /root/teslausb-backup-$(date +%Y%m%d).tar.gz /root/bin/

# Neue Files kopieren
cp run/* /root/bin/
chmod 600 /root/.teslaCam*Credentials

# Neustart
reboot
```

## 📝 Changelog

### v2.0.0 - Security-Hardening Release
- Alle `eval`-Aufrufe entfernt (Command Injection Prevention)
- Alle `source`-Aufrufe durch sicheres Parsing ersetzt (Code Execution Prevention)
- File Locking mit `flock` hinzugefügt (Race Condition Prevention)
- Atomare Verschiebe-Operationen implementiert
- Signal-Handler für Graceful Shutdown hinzugefügt
- Log-Sanitisierung implementiert (Injection Prevention)
- Exponentiellen Backoff für Retries hinzugefügt
- URL-Encoding für GitHub-Downloads hinzugefügt
- DNS-Server konfigurierbar gemacht
- Umfassende Test-Suite hinzugefügt (43 Tests)

## 🤝 Attribution

Dieses Projekt ist ein sicherheitsgehärteter Fork von [TeslaUSB](https://github.com/cimryan/teslausb) von cimryan.

Originale Projekt: https://github.com/cimryan/teslausb

Alle originalen Funktionen sind erhalten. Sicherheitsfixes werden als Community-Service bereitgestellt.

## 📄 Lizenz

Gleich wie das originale TeslaUSB-Projekt. Siehe [LICENSE](LICENSE) Datei.

## ⚠️ Disclaimer

Diese Software wird "wie sie ist" bereitgestellt. Obwohl wir umfassende Sicherheitsfixes und Tests implementiert haben:
1. Immer erst in einer Nicht-Produktionsumgebung testen
2. Backups der Dashcam-Aufnahmen aufbewahren
3. Funktionalität nach Updates verifizieren

Benutzung auf eigene Gefahr.

---

**Made with ⚡ by Zyrial96**
