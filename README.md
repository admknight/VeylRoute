<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,14,18&height=185&section=header&text=VeylRoute&fontSize=58&fontColor=ffffff&animation=twinkling&fontAlignY=35&desc=Privacy%20Routing%20Control%20Center&descSize=18&descAlignY=57" width="100%" alt="VeylRoute — Privacy Routing Control Center">

**Your connection. Your route. Your privacy.**

[![Windows qualification & builds](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml/badge.svg)](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-43A7FF.svg)](LICENSE)
[![Windows release](https://img.shields.io/github/v/release/admknight/VeylRoute?label=Windows&color=43A7FF)](https://github.com/admknight/VeylRoute/releases/latest)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-2376d1.svg)](docs/BUILDING.md)
[![Status: Stable](https://img.shields.io/badge/status-stable-43A7FF)](docs/RELEASE-CHECKLIST.md)

[**Windows builds**](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) · [**Documentation**](docs/BUILDING.md) · [**Security**](SECURITY.md) · [**Roadmap**](docs/PLATFORMS.md) · [**Issues**](https://github.com/admknight/VeylRoute/issues)

</div>

---

## What is VeylRoute?

**VeylRoute** is a Windows-first, graphical privacy-routing control center. It coordinates **Tor + obfs4** with **tun2socks + Wintun** and Windows network protections, without requiring users to manage a collection of terminal commands.

The name blends *Veyl* (a stylized “veil,” suggesting privacy) with *Route* (the path internet traffic takes).

> [!IMPORTANT]
> **Current stable release: Windows v3.0.1 (H6).** GitHub's Windows PowerShell/WPF checks passed **37/37**, and both editions compiled. The H6 binary is identical to its published release candidate and was promoted to stable by project-owner decision. Live self-update behavior was not independently tested here. The executables are unsigned; passing CI is **not** proof of anonymity or leak-free DNS.

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
| **Portable ZIP** | Extractable VeylRoute folder with a native `VeylRoute.exe` GUI launcher | Stable v3.0.1 (unsigned) |
| **Setup EXE** | Inno Setup installer, Start Menu integration and optional desktop shortcut | Stable v3.0.1 (unsigned) |
| **Source** | PowerShell 5.1 / WPF control center, C# launcher source, build scripts and tests | MIT-licensed original project code |

**Download Windows v3.0.1 stable:** [Setup EXE](https://github.com/admknight/VeylRoute/releases/download/v3.0.1/VeylRoute-Windows-v3.0.1-Setup.exe) · [Portable ZIP](https://github.com/admknight/VeylRoute/releases/download/v3.0.1/VeylRoute-Windows-v3.0.1-Portable.zip) · [SHA-256 checksums](https://github.com/admknight/VeylRoute/releases/download/v3.0.1/SHA256SUMS.txt) · [Release notes](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1).

These are **unsigned stable-release binaries**, designated stable following the project owner's report of successful Windows testing. The separate [GitHub Actions build history](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) records source qualification and compilation. Downloaded Tor, Wintun and tun2socks binaries are **not bundled** with release/source artifacts.

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

## About VeylRoute and smart updates

The **v3.0.1 (H6) stable release** adds a dedicated **About VeylRoute** page in place of the old sidebar copyright footer, with app/version details, developer credit **Adam Knight (@admknight)**, MIT acknowledgements and a simple **Check for updates** / **Download & update** flow.

The updater deliberately distinguishes an **installed Setup edition** from a **Portable edition** using an explicit edition marker. It checks **stable GitHub releases**, selects only the matching Setup EXE or portable ZIP, verifies the published SHA-256 checksum, and requires a disconnected session. Installed editions run the normal installer after the GUI exits; portable editions back up and update application files without replacing configuration, Tor, tun2socks or runtime data. The detailed Tor component updater remains on **Versions & updates**.

**Current stable:** [v3.0.1](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1). The [v3.0.1 RC](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1-rc1) is retained as a byte-identical, historical preview.

GitHub's Windows runner passed **37/37** isolated checks and compiled both H6 packages; the project owner authorized stable promotion of those same files. Live portable self-update, Setup upgrade and rollback are not independently demonstrated here. The prior stable [v3.0.0](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0) remains available as an earlier version.

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

On pushes and pull requests touching the application, [GitHub Actions](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) runs isolated checks on a Windows runner. Successful runs upload a portable ZIP, a setup EXE and SHA-256 checksums. Routine builds do **not** perform live Tor/Wintun traffic tests, automatically publish public Releases or sign binaries.

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
| **Windows 10/11 x64** | v3.0.1 stable release (H6 binaries) |
| **macOS** | Planned — no app/build yet |
| **Linux** | [Experimental v0.1.0 CLI/GUI and Debian/portable builds](platforms/linux/README.md); **not live privacy-qualified** |
| **Android** | Planned — no app/build yet |

Cross-platform editions require independent routing, permissions and test gates. Linux now has its own [Tor TransPort / nftables controller, GUI, recovery workflow and package builds](platforms/linux/README.md), with [isolated Linux CI](https://github.com/admknight/VeylRoute/actions/runs/44585890987). **These developer artifacts are not a production Linux privacy release**: end-to-end Tor traffic, DNS/IPv6 leak behavior and recovery in a user-owned Linux runtime are not independently qualified. Windows PowerShell/WPF does not automatically run on Linux. See the [platform roadmap](docs/PLATFORMS.md).

## Security, attribution and licensing

Privacy-routing software deserves careful scrutiny. Security problems should be handled using [SECURITY.md](SECURITY.md), without posting private bridges, session state, IP addresses, Tor control cookies or credentials in public issues.

**Original VeylRoute source:** [MIT License](LICENSE), with the project's public developer attribution as **Adam Knight (@admknight)** in the current source. Public GitHub maintainer: **Adam Knight (@admknight)**. MIT applies to this repository's original code and documentation; **Tor, lyrebird, Wintun, tun2socks and other third-party tools retain their own licenses** and are not redistributed by this repository. See [third-party notices](docs/THIRD-PARTY.md).

Contributions: [CONTRIBUTING.md](CONTRIBUTING.md). Release gates: [RELEASE-CHECKLIST.md](docs/RELEASE-CHECKLIST.md).

---

<div align="center">

**Maintained by [Adam Knight (@admknight)](https://github.com/admknight)**  
[Portfolio](https://admknight.github.io/) · [Source](https://github.com/admknight/VeylRoute) · [Actions](https://github.com/admknight/VeylRoute/actions) · [Issue tracker](https://github.com/admknight/VeylRoute/issues)

</div>
