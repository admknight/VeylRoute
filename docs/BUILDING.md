# Building VeylRoute for Windows

**Current release source:** Windows v3.0 RC1 H5; original VeylRoute source is [MIT licensed](../LICENSE).

VeylRoute runs on Windows PowerShell 5.1 and WPF. Its `VeylRoute.exe` is a native C# x64 **launcher** for the PowerShell/WPF control center, not a C# rewrite of the TorTunnel networking engine.

## Download compiled builds

The [unsigned H5 GitHub prerelease](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0-rc1-h5) contains:
- `VeylRoute-Windows-v3.0-RC1-H5-Portable.zip` — extractable application and launcher
- `VeylRoute-Windows-v3.0-RC1-H5-Setup.exe` — Inno Setup installer
- `SHA256SUMS.txt` — package SHA-256 hashes

These were compiled by [Windows Actions Run #3](https://github.com/admknight/VeylRoute/actions/runs/44507797802) at commit `c34df13aea2c208b2c543205bdc500a79c4e8509`. The native PowerShell/WPF isolated qualification passed **31/31**, and both build jobs passed. The binaries remain **unsigned, not production-verified**.

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

The [release checklist](RELEASE-CHECKLIST.md) records which checks remain unresolved, including native GUI launch, install/uninstall, live New Circuit, DNS containment and fail-closed recovery. A compiled executable alone is **not** an anonymity or privacy guarantee.
