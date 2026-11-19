# Platform roadmap

| Platform | Current state | Required future work |
| --- | --- | --- |
| **Windows 10/11 x64** | PowerShell 5.1/WPF TorTunnel v3.5.1 engine; v3.0.1 stable release using H6 binaries | Ongoing updates and platform-specific testing |
| **Linux** | **Read-only prerequisite probe + isolated CI added**; no tunnel or VPN implementation | Linux native TUN, DNS, nftables, privilege model, recovery and UI |
| **macOS** | Not implemented | macOS network extension/privilege, packaging, signing and notarization design |
| **Android** | Not implemented | Android VpnService routing and app-lifecycle design |

The first Linux foundation is documented in [platforms/linux/README.md](../platforms/linux/README.md), with a read-only probe and isolated GitHub CI. All future platforms can live in the same repository, but each needs platform-specific code, tests and release gates. The current Windows source is not cross-platform as written. Do not advertise macOS, Linux or Android downloads until code and verification exist.
