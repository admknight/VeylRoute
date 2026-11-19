# Building VeylRoute for Windows

VeylRoute v3.0 RC1 H5 is **PowerShell 5.1/WPF** software with a native C# *launcher*, not a native replacement of the networking engine.

[Windows qualification and builds](https://github.com/admknight/VeylRoute/actions/workflows/windows-build.yml) runs on GitHub-hosted Windows runners **after the complete H5 source has been imported**. It first runs the existing isolated test suite and then calls `packaging/BUILD-WINDOWS.ps1 -BuildInstaller`. Output: unsigned Portable ZIP, unsigned Inno Setup EXE, and SHA-256 checksums.

The workflow requires no repository secrets and does not change live network settings on a runner. A successful build is **not** proof of safe installation, routing, leak protection, or recovery. No GitHub Release is automatically published.

## Source import — one-time

The repository starts with documentation and build automation because the full H5 source ZIP must be imported as individual version-controlled files. Clone this repository and run `tools/IMPORT-H5.ps1` with the exact H5 full-candidate ZIP. Review the diff and any contact details before committing and pushing. The ZIP itself must **not** be committed.

## Local Windows compilation

From the complete source root on Windows 10/11 x64:

```powershell
.\tests\VERIFY-WINDOWS.cmd
.\packaging\BUILD-WINDOWS.ps1
.\packaging\BUILD-WINDOWS.ps1 -BuildInstaller
```

The final command requires Inno Setup (6 or 7). Output is `VeylRoute.exe` and `packaging/output/VeylRoute-Windows-v3.0-RC1-H5-Setup.exe`. Windows PowerShell 5.1 and UAC elevation remain required at runtime. Tor, Wintun and tun2socks binaries are deliberately excluded from source builds and must be installed through their separate verification/provisioning flow.

Use a disposable Windows test machine to verify the installer, first-run provisioning, upgrade, uninstall, UAC cancellation and recovery. Consult [release checks](RELEASE-CHECKLIST.md).
