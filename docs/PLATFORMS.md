# Platform roadmap

| Platform | Current state | Required future work |
| --- | --- | --- |
| **Windows 10/11 x64** | PowerShell 5.1/WPF TorTunnel v3.5.1 engine; v3.0.1 stable release using H6 binaries | Ongoing updates and platform-specific testing |
| **Linux** | **Experimental v0.2.0** Tor transparent routing controller, 11-page Tk GUI, official icons, XDG menu/dock identity, optional tray, portable menu shortcuts, GUI prefs and Linux-only verified update flow; 26 isolated tests and Debian/portable packages | Live Tor/DNS/IPv6 containment, fail-closed/crash recovery, install/upgrade, distro tray/polkit testing; SelectedAppsOnly not implemented |
| **macOS** | Not implemented | macOS network extension/privilege, packaging, signing and notarization design |
| **Android** | Not implemented | Android VpnService routing and app-lifecycle design |

Linux source and installation guidance are in [platforms/linux/README.md](../platforms/linux/README.md); [v0.2.0 Linux CI](https://github.com/admknight/VeylRoute/actions/runs/44593706249) passed 26 isolated tests, XDG menu validation, Tk navigation under Xvfb, kernel nftables install/remove **inside an isolated network namespace** and Debian/portable packaging with SHA-256 checksums. The [Linux developer release](https://github.com/admknight/VeylRoute/releases/tag/linux-v0.2.0-experimental) is not privacy-qualified. Live Tor routing, DNS leak containment, safe restoration, installer/desktop behavior and updater rollback still require recorded OS-level testing. SelectedAppsOnly is not available. macOS and Android remain unimplemented; Windows v3.0.1 remains the separately shipped stable platform.
