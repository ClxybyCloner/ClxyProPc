<p align="center">
  <a href="README_fa.md"><img src="https://img.shields.io/badge/🇮🇷_Persian-7c5cff?style=for-the-badge" alt="نسخه فارسی"></a>
</p>

<p align="center">
  <img src="assets/banner.png" alt="CLXY — Fast. Private. Yours." width="100%">
</p>

<p align="center">
  <a href="https://github.com/ClxybyCloner/ClxyProPc/releases/latest"><img src="https://img.shields.io/github/v/release/ClxybyCloner/ClxyProPc?label=latest&color=7c5cff" alt="Latest release"></a>
  <a href="https://github.com/ClxybyCloner/ClxyProPc/releases"><img src="https://img.shields.io/badge/Windows-10%2F11-0078D6?logo=windows&logoColor=white" alt="Windows 10/11"></a>
  <img src="https://img.shields.io/badge/arch-x64-4f8cff" alt="x64">
  <a href="https://github.com/ClxybyCloner/ClxyProPc/releases"><img src="https://img.shields.io/github/downloads/ClxybyCloner/ClxyProPc/total?label=downloads" alt="Total downloads"></a>
</p>

<h1 align="center">ClxyPro — Hyper &amp; Quantum for Windows</h1>

<p align="center">
  <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&weight=600&size=24&duration=2800&pause=1200&color=7C5CFF&center=true&vCenter=true&width=700&lines=Fast.+Private.+Yours.;Official+ClxyPro+Windows+releases;One+click+away+from+the+newest+build" alt="Fast. Private. Yours.">
</p>

This is the **official download & update channel** for the ClxyPro Windows app.
Every release is published here — and the in-app updater checks this exact
repository, so if you're running ClxyPro, you're always one click away from the
newest build.

<p align="center">
  <img src="assets/wave.svg" alt="" width="99%">
</p>

## ⬇️ Download

**Latest: 1.5.36**, released November 28, 2026

- 📦 [Download the Windows x64 zip](https://github.com/ClxybyCloner/ClxyProPc/releases/download/v1.5.36/ClxyPro-1.5.36-Windows-x64.zip)
- [View the SHA-256 checksum](https://github.com/ClxybyCloner/ClxyProPc/releases/download/v1.5.36/SHA256SUMS.txt)
- 🗂️ [Browse all releases](https://github.com/ClxybyCloner/ClxyProPc/releases)

The source code lives in this repository.

---

## ⚡ Why CLXY

- 🌍 **The open internet, on your desktop** — unblock the sites, apps and services restricted in your region. One click and you're in.
- 🚀 **Built for speed** — multi-layer routing on a Go-powered core with HTTP/2 and HTTP/3 (QUIC) stays fast and stable, even on flaky connections.
- 🔒 **Your traffic stays yours** — a real encrypted VPN tunnel for the whole device, with per-app control over what goes through CLXY.
- 👨‍👩‍👧 **One subscription for everyone** — share your connection with nearby devices through the LAN proxy (SOCKS5 `1081`).
- 👆 **No setup headaches** — open the app, tap connect, done.
- 🔄 **Always up to date** — the app notifies you the moment a new build is out; nothing installs without your approval.
- 🪶 **Light on your PC** — just ~34 MB to download, smooth on Windows 10 and 11.

---

## Advanced VPN Routing

CLXY routes traffic through a multi-layered path — not a single VPN hop:

This architecture combines Xray technology with the Mozilla VPN infrastructure to establish a multi-layered network communication path. Its primary goal is to improve traffic management flexibility, isolate network routes, and provide more precise control over inbound and outbound traffic.

Features:

* Multi-Layer Routing: Establishes a chained communication path between the VPN ingress and egress layers.
* Mozilla VPN Integration: Leverages WireGuard infrastructure to manage outbound traffic routing.
* Smart Traffic Routing: Directs traffic based on predefined routing policies.
* Dedicated Tunnel Management: Provides independent control over the outbound tunnel and its connection status.
* IP Leak Protection: Prevents exposure of the original server IP in the event of a tunnel failure.
* Fault Handling & Recovery: Incorporates mechanisms for connection monitoring and automatic route recovery.

Network Architecture:

VLESS → Xray Core → Linux Routing → Mozilla VPN → Internet

This architecture is designed to provide a flexible, scalable, and manageable networking infrastructure.

---

## 🖥️ Windows edition — Hyper & Quantum

- **Two engines, one app** — **CLXY Hyper**: the Mozilla VPN egress layer of CLXY's multi-layer routing path, over HTTP/3 MASQUE with automatic exit routing and a live server list with real pings. **CLXY Quantum**: direct anycast mesh with a serial gate, a server list of 16 relays with real TCP pings, and pin-a-relay.
- **100% portable** — no installer. Extract anywhere (Desktop, USB drive) and run. All settings and credentials live in `user-data\` beside the executable — nothing in the registry, nothing in `%APPDATA%`.
- **Two modes** — **VPN mode**: system-wide routing through a Wintun TUN adapter. **Proxy mode**: local SOCKS5 (`127.0.0.1:1080`) and HTTP (`127.0.0.1:8080`) proxy, with optional LAN sharing (`:1081`). No elevation needed for proxy mode.
- **In-app updater that doesn't give up** — downloads run in the background and resume if you close the dialog; install & restart when the download is ready.
- **Desktop integration** — system tray icon with live connection state, Connect / Disconnect from the tray, Windows toast notifications, and split tunneling (per-program bypass list).

---

## CLXY core architecture

CLXY pairs a Flutter interface with a Go networking core. The core runs as a sidecar daemon beside the app — the client-side end of CLXY's multi-layer routing path. The UI uses a local bridge and loopback API to manage settings and read connection status, while the core handles network traffic.

In VPN mode, a Wintun adapter creates a virtual TUN interface. A user-space TCP/IP stack processes packets and forwards TCP connections to the core's SOCKS5 proxy. The built-in DNS resolver maps domain names to temporary IP addresses so routing rules can still match domains. These rules choose whether to use the proxy, connect directly, or block a connection. App selection controls which apps use the VPN.

The core connects to the gateway over HTTP/2 CONNECT (TLS) or HTTP/3 CONNECT (QUIC). From there, traffic follows CLXY's multi-layer path: VLESS → Xray Core → Linux Routing → Mozilla VPN → Internet. Proxy-only mode uses the same core without creating a device-wide VPN. The Windows VPN path handles TCP and DNS; other UDP traffic is not tunneled.

---


## Install in 60 seconds

1. **Download** the zip from the link above.
2. **Extract it** anywhere — Desktop, USB drive, any folder.
3. **Run `ClxyPro.exe`.** Done.

A subscription is required to use CLXY.

---

## ✅ Verify your download

In PowerShell, calculate the zip's SHA-256:

```powershell
Get-FileHash ClxyPro-1.5.36-Windows-x64.zip -Algorithm SHA256
```

Compare the output with this expected hash:

```text
487d19b26cb4df7b33fcc71ac78fd5c46224680afea85bb7ae42c976962ce479  ClxyPro-1.5.36-Windows-x64.zip
```

If they match, the file is exactly what we published.

---

## 🔄 How updates work

CLXY periodically checks this repo's **Releases** for a newer version. When one
is found, you get a notification inside the app — click it to download, then
confirm the restart yourself. The app never installs anything behind your back.

---

## 📋 Current build specs

| | |
|---|---|
| Package | `ClxyPro-1.5.36-Windows-x64.zip` |
| Version | `1.5.36` |
| Architecture | `x64` |
| Minimum Windows | 10 / 11 |
| Size | 34 MB download / 82 MB extracted |

---

## ❓ FAQ

**Where is the source code?**
The source code is in this repository.

**I need an older version.**
Older builds stay available on the [Releases page](https://github.com/ClxybyCloner/ClxyProPc/releases).

**The LAN proxy asks for nothing — is that safe?**
The LAN SOCKS5 proxy (`1081`) has no password by design, so **only turn it on on a network you trust**, and switch it off when you're done. Anyone on your local network could use it.

---

<p align="center">
  <img src="assets/wave.svg" alt="" width="100%">
</p>

## 📜 Terms

The source and app are distributed under GPLv3. See this repository for the license and source code. Official releases and checksums are published here.
