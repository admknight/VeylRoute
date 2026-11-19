# Platform roadmap

| Platform | Current state | Required future work |
| --- | --- | --- |
| **Windows 10/11 x64** | PowerShell 5.1/WPF TorTunnel v3.5.1 engine; v3.0.0 stable release using H5 binaries | Ongoing updates and platform-specific testing |
| **Linux** | Not implemented | Linux tun, DNS, firewall, privileged service and UI |
| **macOS** | Not implemented | macOS network extension/privilege, packaging, signing and notarization design |
| **Android** | Not implemented | Android VpnService routing and app-lifecycle design |

All future platforms can live in the same repository, but each will need platform-specific code, tests and release gates. The current Windows source is not cross-platform as written. Do not advertise macOS, Linux or Android downloads until code and verification exist.
