<div align="center">

# VeylRoute

**Privacy Routing Control Center**  
*Your connection. Your route. Your privacy.*

[![Windows qualification and builds](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml/badge.svg)](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml)
[![Windows](https://img.shields.io/badge/Windows-10%2F11%20x64-2376d1)](docs/BUILDING.md)
[![Release status](https://img.shields.io/badge/status-RC%20%2F%20qualification-orange)](docs/RELEASE-CHECKLIST.md)

</div>

---

VeylRoute is a **Windows-first privacy-routing control center** built around Tor, obfs4, Wintun and tun2socks. It provides a GUI for connecting, monitoring privacy safeguards, changing Tor circuits, and restoring Windows networking. The current implementation uses **Windows PowerShell 5.1 and WPF**; the native EXE is a launcher, **not a rewrite of the network engine**.

> **Current source baseline:** Windows v3.0 RC1 H5 (qualification candidate). H4's isolated Windows tests passed 26/26 in the user's environment. H5 New Circuit, installer, privacy containment, and recovery paths still require their own live qualification. There is **no production-ready or leak-free claim**.

## Windows candidate features

- **SystemWide** and **SelectedAppsOnly** routing, guided preflight, status, health and recovery.
- Signed Tor Expert Bundle setup workflow and obfs4 bridge support.
- Exit-country preferences and manual **New circuit** request. A new circuit does **not** guarantee a changed public IP.
- Live Activity diagnostics, connection progress and cancellation.
- Overview indicators for Tor routing, DNS safeguards, IPv6 and firewall state. Local checks **do not prove DNS leak-free operation**.
- **Portable application** and **Setup EXE** build targets, both preserving the existing PowerShell/WPF application.

## Get and build VeylRoute

| Edition | Delivery | Status |
| --- | --- | --- |
| **Windows Portable** | Extractable ZIP with native `VeylRoute.exe` launcher | RC build candidate |
| **Windows Setup** | Conventional Inno Setup EXE with shortcuts | RC build candidate |
| **macOS / Linux / Android** | Future platform-specific implementations | Not implemented |

The [Windows build workflow](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) runs isolated qualification, compiles the launcher and installer, and uploads **unsigned Actions artifacts** after the full H5 source is imported. It does **not** publish releases or claim Windows runtime/privacy testing.

See [Building](docs/BUILDING.md), [Release checklist](docs/RELEASE-CHECKLIST.md) and [Platform roadmap](docs/PLATFORMS.md).

### Portable first run

On Windows 10/11 x64, extract a validated candidate into a writable local folder. Start `VeylRoute.exe` or the source-only `VeylRoute.vbs`, approve elevation, provision the missing components using the built-in verification flow, configure bridges and routing, then run **Preflight → Connect → Health**. Use **Disconnect** to restore normal networking.

This repository does **not** redistribute Tor, Wintun, tun2socks or lyrebird binaries. Do not delete active session-state files or forcibly terminate recovery while routing changes may still exist.

## Security and licensing

VeylRoute modifies Windows routes, DNS and firewall rules. Edge routed through Tor does **not** provide Tor Browser-level anonymity. No network software can be declared leak-free solely from an IP check, GUI status, or script parser pass. See [Security](SECURITY.md) and [Third-party components](docs/THIRD-PARTY.md).

This public repository **does not yet declare a reuse license**. Existing source-file copyrights are preserved; consult [License status](docs/LICENSE-STATUS.md) before reuse or redistribution.

<div align="center">

Maintained on GitHub by **[Adam Knight (@admknight)](https://github.com/admknight)**

[Source](https://github.com/admknight/VeylRoute) · [Actions](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) · [Issues](https://github.com/admknight/VeylRoute/issues) · [Portfolio](https://admknight.github.io/)

</div>
