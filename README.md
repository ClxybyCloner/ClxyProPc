# ClxyPro for Windows (Portable)

> Exact Windows Portable clone of the Android [ClxyPro](https://github.com/ClxybyCloner/ClxyPro) client (v1.5.11).

ClxyPro for Windows is a high-performance, completely portable VPN and Proxy client designed for Windows 10 and 11 (x64). It faithfully replicates every screen, color, animation, flow, and behavior from the Android edition, featuring dual-core acceleration, quantum serial authentication, and zero-relay direct paths.

[![Build Windows Portable](https://github.com/ClxybyCloner/ClxyProPc/actions/workflows/build.yml/badge.svg)](https://github.com/ClxybyCloner/ClxyProPc/actions/workflows/build.yml)
[![Latest Release](https://img.shields.io/github/v/release/ClxybyCloner/ClxyProPc?color=blue&label=Release)](https://github.com/ClxybyCloner/ClxyProPc/releases/tag/v1.5.24)
[![Download Zip](https://img.shields.io/badge/Download-Portable%20Zip%20(v1.5.24)-success?logo=windows)](https://github.com/ClxybyCloner/ClxyProPc/releases/download/v1.5.24/ClxyPro-1.5.24-Windows-x64.zip)

---

## ✨ Features

- **100% Portable (Zero Installer)**: Run from anywhere (Desktop, USB flash drive, external drive). No registry writes, no `%APPDATA%` pollution. All settings and credentials reside in `user-data\` beside the executable.
- **Dual-Engine Architecture**:
  - **CLXY Hyper**: Mozilla Firefox HTTP/3 MASQUE direct engine with automatic exit routing and reachability validation.
  - **CLXY Quantum**: Aether direct anycast mesh with SHA-256 serial gate protection and direct MASQUE transport.
- **Dual Operating Modes**:
  - **VPN Mode**: System-wide full-device routing via Wintun userspace TUN adapter.
  - **Proxy Mode**: Pure userspace local SOCKS5 (`127.0.0.1:1080`) and HTTP (`127.0.0.1:8080`) proxy with optional LAN sharing (`:1081`). Zero elevation required!
- **Zero Relay**: All traffic connects directly to edge endpoints. No intermediary relays, no shared pools, no tracking.
- **Pixel-Perfect Cosmic UI**:
  - Exact design tokens, fonts (`Inter` and `Vazirmatn`), and colors from Android source.
  - Interactive Dotted World Map with animated shimmer waves.
  - Dynamic multi-ring pulsing Cosmic Power Button with breathing idle states.
  - Real-time animated route visualization with live packet flow and country flags.
  - Display-only fake VLESS URIs formatted for server display.
  - Live upload / download telemetry and tabular connection timer.
- **Desktop Integration**:
  - System tray icon showing live connection state (`connected` / `disconnected`).
  - Tray menu with Connect, Disconnect, Open Window, and Quit actions.
  - Windows Toast notifications for connection status and version updates.
  - Split Tunneling (per-program executable bypass list).
  - Background core lifetime bound to app process (stdin pipe).

---

## 📁 Portable Layout

When extracted, the portable directory structure is:

```text
ClxyPro/
├── ClxyPro.exe               # Main Windows Desktop executable (Flutter runner)
├── data/                     # Flutter assets, fonts, icons, flags, and binaries
│   ├── app.so
│   ├── icudtl.dat
│   └── flutter_assets/
├── flutter_windows.dll       # Flutter Windows runtime
├── core/
│   ├── clxy-vpn-core.exe     # Go Core sidecar daemon
│   └── clxy-vpn-tun.exe      # Windows TUN service helper
├── user-data/                # Auto-created on first run (settings, session, logs)
│   ├── settings.json
│   ├── session.txt
│   └── local-api.token
└── README.txt                # Quick usage guide
```

---

## 🛠️ Building Locally

### Prerequisites

- **Windows 10 / 11 (x64)**
- **Git**
- **Go 1.23+**
- **Flutter 3.24+ (Stable channel)**
- **Visual Studio 2022** with *Desktop development with C++* and Windows SDK

### Build Command

Run the automated PowerShell build script:

```powershell
./scripts/build-windows.ps1
```

The script will:
1. Build the Flutter Windows desktop application in release mode.
2. Compile `clxy-vpn-core.exe` and `clxy-vpn-tun.exe` with symbol stripping and trimpath.
3. Assemble the portable package folder.
4. Generate the compressed release archive: `dist/ClxyPro-1.5.24-Windows-x64.zip`.

---

## 🚀 Continuous Integration & Automated Builds

Every commit to `main` and tag `v*` triggers the GitHub Actions workflow (`.github/workflows/build.yml`):
- Runs on `windows-latest`
- Builds the portable zip archive
- Attaches artifacts to workflow runs
- Publishes rolling pre-releases on `latest` and formal GitHub Releases on version tags (`v1.5.24`)

---

## 🛡️ License

Open source under the Apache 2.0 / MIT License.
ClxyPro is developed and maintained by [ClxybyCloner](https://github.com/ClxybyCloner).