<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,14,18&height=185&section=header&text=VeylRoute&fontSize=58&fontColor=ffffff&animation=twinkling&fontAlignY=35&desc=Privacy%20Routing%20Control%20Center&descSize=18&descAlignY=57" width="100%" alt="VeylRoute — Privacy Routing Control Center">

**Your connection. Your route. Your privacy.**

[![Windows qualification & builds](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml/badge.svg)](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-43A7FF.svg)](LICENSE)
[![Windows prerelease](https://img.shields.io/github/v/release/admknight/VeylRoute?include_prereleases&label=Windows%20RC&color=f4a340)](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0-rc1-h5)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-2376d1.svg)](docs/BUILDING.md)
[![Status: Release Candidate](https://img.shields.io/badge/status-RC%20candidate-f4a340.svg)](docs/RELEASE-CHECKLIST.md)

[**Windows builds**](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) · [**Documentation**](docs/BUILDING.md) · [**Security**](SECURITY.md) · [**Roadmap**](docs/PLATFORMS.md) · [**Issues**](https://github.com/admknight/VeylRoute/issues)

</div>

---

## What is VeylRoute?

**VeylRoute** is a Windows-first, graphical privacy-routing control center. It coordinates **Tor + obfs4** with **tun2socks + Wintun** and Windows network protections, without requiring users to manage a collection of terminal commands.

The name blends *Veyl* (a stylized “veil,” suggesting privacy) with *Route* (the path internet traffic takes).

> [!IMPORTANT]
> **Release state: Windows v3.0 RC1 H5 — qualification candidate, not production-verified.** The earlier H4 Windows isolated qualification passed 26/26 on a user-operated machine; H5's live New Circuit behavior, full network/DNS containment, cancellation, selected-app routing, installation, and uninstall still require additional evidence. A green CI badge means the isolated Windows build/tests passed; it is **not** a guarantee of anonymity or leak-free operation.

## Features at a glance

| Area | What the current Windows implementation offers |
| :--- | :--- |
| **Overview** | Connection state, live health summary, exit IP and compact privacy indicators |
| **Connection** | Tor bootstrap progress, obfs4 bridge support, cancellation and recovery paths |
| **Routing** | **SystemWide** and **SelectedAppsOnly** modes, with explicit configuration |
| **Exit locations** | Fixed-country, selected-country pool and country-availability information |
| **New circuit** | Authenticated Tor **NEWNYM** request, rate limiting, and an exit-IP comparison |
| **Diagnostics** | Status, Preflight, Health, Activity history and classified messages |
| **Safeguards** | Strict DoH / DNS firewall settings, IPv6 configuration, Edge controls, session restoration |
| **Updates** | Component inventory, verified Tor Expert Bundle workflow and package management |

### Connection health is not a promise of anonymity

VeylRoute distinguishes **Tor connected**, **safeguards configured**, and **independently confirmed protection**. In particular, DoH and firewall-rule presence cannot by themselves prove that every DNS request stayed inside Tor. A normal browser routed through Tor is **not** equivalent to Tor Browser's fingerprinting and isolation defenses.

Tor can acknowledge **New circuit** without assigning a new public IP. Existing connections are not forcibly moved to new circuits; the selected country restrictions remain in effect.

## Windows editions

| Edition | What you get | Status |
| --- | --- | --- |
| **Portable ZIP** | Extractable VeylRoute folder with a native `VeylRoute.exe` GUI launcher | Unsigned RC build target |
| **Setup EXE** | Inno Setup installer, Start Menu integration and optional desktop shortcut | Unsigned RC build target |
| **Source** | PowerShell 5.1 / WPF control center, C# launcher source, build scripts and tests | MIT-licensed original project code |

**Download Windows RC1 H5 (unsigned pre-release):** [Setup EXE](https://github.com/admknight/VeylRoute/releases/download/v3.0.0-rc1-h5/VeylRoute-Windows-v3.0-RC1-H5-Setup.exe) · [Portable ZIP](https://github.com/admknight/VeylRoute/releases/download/v3.0.0-rc1-h5/VeylRoute-Windows-v3.0-RC1-H5-Portable.zip) · [SHA-256 checksums](https://github.com/admknight/VeylRoute/releases/download/v3.0.0-rc1-h5/SHA256SUMS.txt) · [Release notes](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0-rc1-h5).

These are **unsigned qualification candidates**, not yet production-verified. The separate [GitHub Actions build history](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) records their source qualification and compilation. Downloaded Tor, Wintun and tun2socks binaries are **not bundled** with release/source artifacts.

### Basic requirements

- Windows 10 or Windows 11, **x64**
- Windows PowerShell **5.1**, .NET Framework 4.x and WPF
- Administrator approval (required for network-routing and firewall operations)
- Internet connectivity or verified local component imports for first-time provisioning
- A writable local installation/data location; **do not relocate an active session**

### First run

1. Extract the portable build or install the setup edition **only on a system where no old VeylRoute session is active**.
2. Launch **VeylRoute** and approve the required Windows elevation.
3. Use its component setup to provision and verify **Tor + lyrebird**, **Wintun**, and **tun2socks**. Add obfs4 bridges when required; never publish private bridge lines.
4. Choose your routing mode and exit preferences, save settings, then run **Preflight**.
5. **Connect → Health → Review Overview**. Use **Disconnect** for normal restoration, and **Recover** if a session does not restore cleanly.

The setup edition does **not** automatically migrate an existing portable folder or install third-party networking binaries. See [Building and installation notes](docs/BUILDING.md).

## How the Windows version works

```text
VeylRoute.exe (native C# launcher)
             │ UAC / Windows PowerShell 5.1
             ▼
WPF Control Center + GUI Worker
             │ status / config / log streaming
             ▼
TorTunnel Universal v3.5.1 engine
       ├── Tor + lyrebird (obfs4)
       ├── tun2socks + Wintun
       ├── Windows routing, DNS & firewall controls
       └── Stop / recovery and state restoration
```

The native EXE is a **launcher around the existing WPF/PowerShell application**, not a new native Tor networking implementation. Internal legacy engine filenames are retained where necessary for backward compatibility.

## Build and qualify on Windows

```powershell
# Windows PowerShell 5.1 / no live network changes:
.\tests\VERIFY-WINDOWS.cmd

# Build native Windows launcher:
.\packaging\BUILD-WINDOWS.ps1

# Build launcher and Inno Setup installer (requires Inno Setup):
.\packaging\BUILD-WINDOWS.ps1 -BuildInstaller
```

On pushes and pull requests touching the application, [GitHub Actions](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) runs isolated checks on a Windows runner. Successful runs upload a portable ZIP, a setup EXE and SHA-256 checksums. The workflow does **not** conduct real Tor/Wintun traffic tests, automatically create public Releases or sign binaries.

### Repository map

```text
.github/workflows/  Windows build and qualification
_internal/          TorTunnel engine, workers, recovery and updater
ui/                 PowerShell/WPF GUI and icons
config/             Public defaults (private bridges excluded)
packaging/          Native EXE launcher and Inno Setup sources
tests/              Isolated Windows qualification suite
docs/               Setup, security, provenance and future platforms
tools/              Repository maintenance/import helpers
```

## Other platforms — future work

| Platform | Status |
| --- | --- |
| **Windows 10/11 x64** | Active RC1 H5 implementation |
| **macOS** | Planned — no app/build yet |
| **Linux** | Planned — no app/build yet |
| **Android** | Planned — no app/build yet |

Cross-platform editions will require their own native system routing, permissions and testing; Windows PowerShell/WPF does not automatically run on other operating systems. See the [platform roadmap](docs/PLATFORMS.md).

## Security, attribution and licensing

Privacy-routing software deserves careful scrutiny. Security problems should be handled using [SECURITY.md](SECURITY.md), without posting private bridges, session state, IP addresses, Tor control cookies or credentials in public issues.

**Original VeylRoute source:** [MIT License](LICENSE) — Copyright © 2026 Zahid Hussain / Scopewise Consulting. MIT applies to this repository's original code and documentation; **Tor, lyrebird, Wintun, tun2socks and other third-party tools retain their own licenses** and are not redistributed by this repository. See [third-party notices](docs/THIRD-PARTY.md).

Contributions: [CONTRIBUTING.md](CONTRIBUTING.md). Release gates: [RELEASE-CHECKLIST.md](docs/RELEASE-CHECKLIST.md).

---

<div align="center">

**Maintained by [Adam Knight (@admknight)](https://github.com/admknight)**  
[Portfolio](https://admknight.github.io/) · [Source](https://github.com/admknight/VeylRoute) · [Actions](https://github.com/admknight/VeylRoute/actions) · [Issue tracker](https://github.com/admknight/VeylRoute/issues)

</div>
