# Platform roadmap

| Platform | Current state | Required future work |
| --- | --- | --- |
| **Windows 10/11 x64** | PowerShell 5.1/WPF TorTunnel v3.5.1 engine; v3.0.1 stable release using H6 binaries | Ongoing updates and platform-specific testing |
| **Linux** | **Experimental v0.1.0** Tor TransPort/DNSPort + nftables CLI and Tk GUI, 14 isolated tests, isolated nft kernel test, Debian and portable packages | Live Tor bootstrap, DNS/IPv6 containment, fail-closed recovery, install/upgrade and desktop validation; SelectedAppsOnly and app updater still unimplemented |
| **macOS** | Not implemented | macOS network extension/privilege, packaging, signing and notarization design |
| **Android** | Not implemented | Android VpnService routing and app-lifecycle design |

The Linux application source and installation notes are in [platforms/linux/README.md](../platforms/linux/README.md); the [Linux build run](https://github.com/admknight/VeylRoute/actions/runs/44585890987) has verified isolated unit/contract tests, kernel nftables rule installation/removal **in a new network namespace**, and unsigned package construction. The Linux artifacts are **development candidates**, not privacy-qualified releases. Do not advertise Linux as stable until real Linux systemwide routing, DNS leak containment, safe restoration and installer/desktop testing have observable PASS evidence. macOS and Android remain unimplemented. The current Windows source is not cross-platform as written.
