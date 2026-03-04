# Adṛśya-Setu — The Invisible Bridge

```
   ___       _  __ _           ___     _
  / _ \   __| |/ _(_)_ __  ___/ __| __| |_  _
 | (_) | / _` |  _| |  _ \/ -_\__ \/ _` | || |
  \___/ /_/ \____|_|____/\___|___/\__,_|\___,/
              A d ṛ ś y a - S e t u  v2.0
```

> **Adṛśya** (अदृश्य) — Invisible · **Setu** (सेतु) — Bridge  
> Automatically rotate your Tor exit node IP on a configurable interval,  
> keeping your network identity in constant, silent motion.

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Requirements](#requirements)
- [File Structure](#file-structure)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Security Notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)

---

## Overview

Adṛśya-Setu is a Bash-based Tor IP rotation toolkit. It signals Tor to build a fresh circuit at regular intervals, logs each new exit-node IP, and optionally runs as a hardened systemd background service. A separate interactive mode provides a live terminal dashboard showing uptime, rotation count, and IP history.

---

## Features

| Feature | Details |
|---|---|
| **Automatic IP rotation** | Sends `SIGNAL NEWNYM` via Tor's ControlPort on a user-defined interval |
| **Live dashboard** | Flicker-free terminal UI with uptime, rotation counter, and 6-entry IP history |
| **Systemd service** | Runs headlessly at boot with automatic restart and systemd hardening |
| **Log rotation** | Keeps log files lean — auto-trims after 5 000 lines |
| **Atomic stats** | Rotation count, last IP, and uptime written safely with temp-file swaps |
| **Resilient startup** | Retries Tor connection up to 12 times before giving up |
| **Multi-distro support** | Arch / Manjaro, Debian / Ubuntu / Kali / Parrot, Fedora, openSUSE |
| **Safe installer** | Backs up `torrc` before modification; validates interval ≥ 10 s |

---

## Requirements

| Dependency | Purpose |
|---|---|
| `tor` | Tor daemon (SOCKS5 proxy + ControlPort) |
| `curl` | Fetch current exit-node IP from Tor Project API |
| `jq` | Parse JSON response |
| `xxd` | Read binary auth cookie as hex |
| `nc` (netcat) | Send control commands to Tor ControlPort |
| `systemd` | Run the rotation service at boot (Linux only) |

> All dependencies are installed automatically by `setup.sh` or `ip-changer.sh`.

---

## File Structure

```
adrishya-setu/
├── setup.sh                # One-shot installer & service deployer
├── ip-changer.sh           # Interactive foreground mode with live dashboard
├── change_tor_ip.sh        # Core rotation engine (called by systemd service)
└── adrishya-setu.service   # Systemd unit file
```

After installation, the following files are created in `$HOME`:

```
~/
├── change_tor_ip.sh        # Deployed core script
├── ip-changer.sh           # Deployed interactive script
├── adrishya_setu.log       # Rotation log  (auto-rotated at 5 000 lines)
└── adrishya_setu.stats     # Live stats    (rotations, last IP, uptime)
```

---

## Installation

### Quick Install (recommended)

```bash
git clone https://github.com/dipendrabist/adrishya-setu
cd adrishya-setu
sudo bash setup.sh
```

`setup.sh` will:
1. Detect your distro and install all dependencies
2. Add your user to the `tor` / `debian-tor` group
3. Patch `/etc/tor/torrc` with ControlPort settings (backup saved automatically)
4. Ask for your preferred rotation interval (minimum 10 s)
5. Deploy all scripts to `$HOME` and enable the systemd service

> **Note:** You may need to log out and back in after installation for group membership changes to take effect.

---

## Usage

### Systemd Service (background, auto-starts on boot)

```bash
# Check service status
systemctl status adrishya-setu

# Follow live logs via journald
journalctl -fu adrishya-setu

# Stop / start / restart
sudo systemctl stop adrishya-setu
sudo systemctl start adrishya-setu
sudo systemctl restart adrishya-setu

# Disable autostart
sudo systemctl disable adrishya-setu
```

### Interactive Mode (live dashboard in terminal)

```bash
sudo ~/ip-changer.sh
# or, from the project directory:
sudo bash ip-changer.sh
```

The dashboard displays:

```
┌──────────────────────────────────────────────────────┐
│  Status          ● RUNNING                           │
│  Uptime          00:04:37                            │
│  Rotations       27                                  │
│  Current IP      185.220.101.47                      │
│  Interval        10s                                 │
│                                                      │
│  Recent IP History                                   │
│  • 14:22:01 → 185.220.101.47                        │
│  • 14:21:51 → 176.10.99.200                         │
│  • 14:21:41 → 45.151.167.10                         │
│  ...                                                 │
└──────────────────────────────────────────────────────┘
```

Press `Ctrl+C` to stop.

### View Rotation Log

```bash
tail -f ~/adrishya_setu.log
```

Example output:
```
2025-06-01 14:21:41 [INFO] Adṛśya-Setu rotation engine started (PID 3821)
2025-06-01 14:21:44 [INFO] ✦ New Exit Node → 45.151.167.10
2025-06-01 14:21:54 [INFO] ✦ New Exit Node → 176.10.99.200
2025-06-01 14:22:04 [INFO] ✦ New Exit Node → 185.220.101.47
```

### View Stats File

```bash
cat ~/adrishya_setu.stats
```

```
ROTATIONS=27
LAST_IP=185.220.101.47
LAST_SEEN=2025-06-01 14:22:04
STARTED=2025-06-01 14:17:27
```

---

## Configuration

### Change the Rotation Interval

**Option A — Re-run the installer** (recommended, updates the service file cleanly):
```bash
sudo systemctl stop adrishya-setu
sudo bash setup.sh
```

**Option B — Edit the service file manually:**
```bash
sudo nano /etc/systemd/system/adrishya-setu.service
# Change: RestartSec=10  →  RestartSec=30
sudo systemctl daemon-reload
sudo systemctl restart adrishya-setu
```

> **Minimum interval:** Tor enforces a 10-second cooldown between `NEWNYM` signals. Values below 10 are automatically raised to 10.

### Tor Configuration

`setup.sh` appends the following to `/etc/tor/torrc` (a backup is saved first):

```
# Adṛśya-Setu — auto-configured
ControlPort 9051
CookieAuthentication 1
CookieAuthFileGroupReadable 1
```

---

## How It Works

```
┌───────────────┐   SIGNAL NEWNYM   ┌──────────────────┐
│  change_      │ ──────────────── ▶ │  Tor ControlPort │
│  tor_ip.sh    │                   │  127.0.0.1:9051  │
└───────────────┘                   └──────────────────┘
        │                                    │
        │  curl --socks5-hostname             │ builds new
        │  127.0.0.1:9050                    │ exit circuit
        ▼                                    ▼
┌───────────────────────┐        ┌──────────────────────┐
│ check.torproject.org  │        │  New Exit Node IP    │
│ /api/ip               │ ◀───── │  assigned            │
└───────────────────────┘        └──────────────────────┘
        │
        ▼
  Logged to ~/adrishya_setu.log
  Stats updated in ~/adrishya_setu.stats
```

1. The systemd service calls `change_tor_ip.sh` on every `RestartSec` interval.
2. The script reads the binary Tor auth cookie and converts it to hex.
3. It opens a TCP connection to `127.0.0.1:9051` (ControlPort) and sends `SIGNAL NEWNYM`.
4. After a 3-second pause (circuit build time), it fetches the current exit IP via the Tor SOCKS5 proxy.
5. The IP is logged to a text file; stats are updated atomically.

---

## Security Notes

- **Tor is a proxy, not a VPN.** Only traffic explicitly routed through `127.0.0.1:9050` uses Tor. System-wide traffic is unaffected unless you configure a transparent proxy separately.
- **Cookie authentication** is used instead of a plain-text password. The auth cookie is readable only by root and members of the `tor` / `debian-tor` group.
- The systemd service is hardened with `NoNewPrivileges`, `PrivateTmp`, and `ProtectSystem=strict` to limit its footprint.
- Frequent `NEWNYM` signals do not guarantee a different exit IP every time — Tor selects from available relays and may occasionally reuse one.
- **Do not use Tor for activities that require high-speed transfers** — relay bandwidth is a shared, volunteer resource.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Cannot read auth cookie` | User not in `tor`/`debian-tor` group | Log out and back in after `setup.sh` |
| `Tor unreachable` after startup | Tor hasn't finished bootstrapping | Wait 30 s; check `systemctl status tor` |
| IP doesn't change | NEWNYM cooldown not elapsed | Increase interval to ≥ 10 s |
| `curl` returns empty IP | Tor circuit still building | Wait one more interval; check Tor logs |
| Service fails to start | `change_tor_ip.sh` path wrong | Re-run `setup.sh` to redeploy |

**Check Tor's own logs:**
```bash
journalctl -u tor --since "10 minutes ago"
```

**Manually test the ControlPort:**
```bash
COOKIE=$(sudo xxd -ps /var/run/tor/control.authcookie | tr -d '\n')
printf 'AUTHENTICATE %s\r\nGETINFO version\r\nQUIT\r\n' "$COOKIE" | nc 127.0.0.1 9051
```

---

> *"Be water. Be invisible. Be the bridge."*