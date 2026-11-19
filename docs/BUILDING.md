# Building VeylRoute for Windows

**Current stable release:** Windows [v3.0.1](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1), using the unchanged qualified H6 build. Original VeylRoute source is [MIT licensed](../LICENSE).

VeylRoute runs on Windows PowerShell 5.1 and WPF. Its `VeylRoute.exe` is a native C# x64 **launcher** for the PowerShell/WPF control center, not a C# rewrite of the TorTunnel networking engine.

## Download compiled builds

The [Windows v3.0.1 stable release](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1) contains the same byte-identical unsigned H6 candidate build:
- `VeylRoute-Windows-v3.0.1-Portable.zip` — extractable application and launcher
- `VeylRoute-Windows-v3.0.1-Setup.exe` — Inno Setup installer
- `SHA256SUMS.txt` — package SHA-256 hashes

These were compiled by [GitHub Windows H6 run](https://github.com/admknight/VeylRoute/actions/runs/44568059908) at commit `cb487027cf34c2bb7761aa686bb042b8e1e20795`. Native PowerShell/WPF isolated qualification passed **37/37** and both packaging jobs passed. The project owner explicitly authorized the unchanged H6 binary to be promoted to stable. The new update path was not independently live-tested here, and binaries remain **unsigned**.

## Build directly from this repository

GitHub Actions runs the isolated Windows qualification and invokes `packaging/BUILD-WINDOWS.ps1 -BuildInstaller`. The workflow produces an unsigned portable archive, an Inno Setup EXE and SHA-256 checksums. It does **not** perform live Tor/Wintun/DNS traffic tests or automatically ship production releases.

To compile locally on Windows 10/11 x64 from the source root:

```powershell
.\tests\VERIFY-WINDOWS.cmd
.\packaging\BUILD-WINDOWS.ps1
.\packaging\BUILD-WINDOWS.ps1 -BuildInstaller
```

The installer step requires Inno Setup 6 or 7. The C# launcher compiles with the Windows .NET Framework x64 compiler, and the GUI still requires Windows PowerShell 5.1 and UAC approval.

## Distribution boundaries

- Both packages contain the [MIT License](../LICENSE); older TorTunnel component filenames remain for backward compatibility.
- Tor Expert Bundle, lyrebird, Wintun and tun2socks **binaries are not bundled**. The application's component-provisioning system must obtain and verify these separately.
- A setup install is **separate from an existing portable installation**; it does not migrate downloaded binaries or user configuration.
- Avoid installing/upgrading/uninstalling over an active session. Verify Stop and full network restoration before moving folders or deleting state.
- Source import from the original H5 ZIP has **already been completed**. The historical `tools/IMPORT-H5.ps1` is retained for provenance; users do **not** need it to build or run the published repository.

The [release evidence record](RELEASE-CHECKLIST.md) distinguishes source/build checks from the owner's stable promotion decision. A compiled executable or a reported working session is **not** a universal anonymity or DNS leak-free guarantee.
