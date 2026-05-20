# Xray VLESS Manager

![Shell](https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![Xray](https://img.shields.io/badge/Core-Xray--core-blue?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)

[中文](README.md) | **English**

![Version](https://img.shields.io/badge/version-v0.1.4-blue?style=flat-square)

**A lightweight Xray-core / VLESS one-click manager that generates common VLESS server configs based on official XTLS/Xray-examples templates.**

> It is designed for quick VPS deployment, server config generation, and client link export. The recommended default is `VLESS + XTLS Vision + REALITY`.

---

## 🎯 Features

- Install / update Xray-core through the official installer
- Generate server configs based on official templates and validate with `xray test -config` before restart
- Auto-generate UUID, REALITY X25519 keys, shortId, WS/XHTTP path, and gRPC serviceName
- Export VLESS URI, key parameters, and client JSON
- Simple menu for config viewing, restart, logs, and uninstall

---

## 🧩 Supported Modes

| Menu | Mode | Official template / docs | Notes |
| --- | --- | --- | --- |
| 2 | VLESS TCP plaintext | `VLESS-TCP` | For testing or reverse-proxy only; not recommended as a public standalone mode |
| 3 | VLESS + XTLS Vision + REALITY | `VLESS-TCP-XTLS-Vision-REALITY` | Recommended default |
| 4 | VLESS TCP + REALITY | `VLESS-TCP-REALITY` | REALITY without Vision flow |
| 5 | VLESS + WebSocket + TLS | `VLESS-WSS-Nginx` / `VLESS-TCP-TLS-WS` | Uses self-signed cert in this script; ACME reverse proxy is better for production |
| 6 | VLESS + gRPC + REALITY | `VLESS-gRPC-REALITY` | Optional REALITY mode |
| 7 | VLESS + XHTTP + REALITY | `VLESS-XHTTP-Reality` | Newer mode; Xray >= v25.3.6 recommended |
| 8 | VLESS Encryption TCP | VLESS Encryption / `xray vlessenc` | Requires both server and client support |

---

## 🚀 Quick Start

```bash
bash <(curl -Ls https://xray.shuijiao.de)
```

Fallback:

```bash
curl -Lo xray-vless.sh https://xray.shuijiao.de
chmod +x xray-vless.sh
./xray-vless.sh
```

---

## 💬 Menu Preview

```text
============================================
 Xray VLESS Manager
 Repo: Xray-VLESS-Manager
 Author: shuijiao
============================================
Install Status: installed / not installed
Run Status: running / stopped

=== Basic ===
 1) Install / update Xray-core
 2) Install VLESS TCP plaintext
 3) Install VLESS + XTLS Vision + REALITY (recommended)
 4) Install VLESS TCP + REALITY
 5) Install VLESS + WebSocket + TLS
 6) Install VLESS + gRPC + REALITY
 7) Install VLESS + XHTTP + REALITY
 8) Install VLESS Encryption TCP

=== Service ===
 9) Show client config
10) Restart Xray
11) Show logs

=== System ===
12) Uninstall Xray
 0) Exit
```

---

## ⚙️ Flow

Most installation modes only require 1-3 inputs:

- Port, default `443`
- REALITY SNI / target, default `www.microsoft.com`
- Domain or path for WS/TLS and XHTTP modes

The script will then:

1. Check / install dependencies
2. Install or reuse Xray-core
3. Generate keys and random parameters
4. Write `/usr/local/etc/xray/config.json`
5. Generate `/usr/local/etc/xray/client.txt` and `client.json`
6. Run `xray test -config /usr/local/etc/xray/config.json`
7. Restart `xray` only after validation passes

---

## ⚠️ Notes

- REALITY target should preferably be an overseas site supporting TLS 1.3 / H2 without forced primary-domain redirects.
- `VLESS TCP plaintext` has no transport-layer security and is not recommended as a public standalone mode.
- `VLESS Encryption` is a newer Xray feature. This script uses `xray vlessenc`; unsupported clients may fail to import or connect.
- `WebSocket + TLS` uses a self-signed cert in this script. For production, Caddy / Nginx / ACME is recommended.
- The script overwrites `/usr/local/etc/xray/config.json`; back up existing complex configs first.

---

## 🛠 Test

Basic static check:

```bash
bash tests/static-check.sh
```

Before every actual restart, the script runs:

```bash
xray test -config /usr/local/etc/xray/config.json
```

---

## ⚙️ Versioning and Releases

- Current version: `v0.1.3`
- Changelog: [`CHANGELOG.md`](CHANGELOG.md)
- GitHub Releases are generated from `CHANGELOG.md`
- Maintainers can publish a new version with:

```bash
./release.sh <version> "release notes"
```

---

## 📄 License

MIT License
