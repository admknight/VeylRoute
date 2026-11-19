# VeylRoute for Windows — v3.0 RC1 H5

**Status: UNSIGNED PRE-RELEASE / QUALIFICATION CANDIDATE**

This build was compiled by [GitHub Actions on Windows](https://github.com/admknight/VeylRoute/actions/runs/44507797802) from commit [c34df13](https://github.com/admknight/VeylRoute/commit/c34df13aea2c208b2c543205bdc500a79c4e8509).

## Downloads

- **Portable ZIP:** `VeylRoute-Windows-v3.0-RC1-H5-Portable.zip` — extract and run `VeylRoute.exe`.
- **Setup EXE:** `VeylRoute-Windows-v3.0-RC1-H5-Setup.exe` — Windows installer (UAC required).
- **SHA256SUMS.txt:** checksums for both packages.

Both contain VeylRoute's original source under the [MIT License](https://github.com/admknight/VeylRoute/blob/main/LICENSE) (Copyright © 2026 Zahid Hussain / Scopewise Consulting). Tor, Wintun, tun2socks and lyrebird binaries are **not included** and remain under their own licenses.

## Included in H5

- WPF Overview, privacy indicators, guided Preflight, Health, Status and categorized Activity logs.
- SystemWide/SelectedAppsOnly routing controls, obfs4 bridges, component provisioning and recovery.
- Authenticated Tor SAFECOOKIE/NEWNYM manual **New circuit** control, with exit-IP comparison.
- Native x64 launcher and Inno Setup-based Windows installer.

## Evidence and limitations

**Passed:** GitHub's Windows PowerShell 5.1/WPF isolated qualification **31/31** and both native launcher / setup compilation jobs. The portable ZIP was inspected for MIT License inclusion and checked against the verified H5 source; package SHA-256 hashes were verified.

**Still unverified:** H5's live SAFECOOKIE/NEWNYM interoperability, SelectedAppsOnly mode, DNS traffic-path containment, fail-closed behavior, cancellation under failure, full post-Disconnect network restoration, first-run binary provisioning and actual setup upgrade/uninstall. The GUI's DNS safeguards do **not** prove all DNS traffic is leak-free. Browser traffic through Tor is not equivalent to Tor Browser-level anonymity.

**Unsigned:** Windows SmartScreen or antivirus warnings may occur. Download only from the linked GitHub release or corresponding Actions run, verify SHA-256, and test on a disposable Windows system until the live gates are completed. Do **not** install over an active Tor session or assume older portable configuration has been migrated.

## SHA-256

```text
a2d630fb1a07139c12da047d329d233a1f4fec0a59031ace209e948a86a2a34f  VeylRoute-Windows-v3.0-RC1-H5-Portable.zip
c8d17a8f17cf9ed1dabd5432f9ace0319887b36d242caae83e8cafce5e76a6d9  VeylRoute-Windows-v3.0-RC1-H5-Setup.exe
```

See [Release acceptance checklist](https://github.com/admknight/VeylRoute/blob/main/docs/RELEASE-CHECKLIST.md), [Security](https://github.com/admknight/VeylRoute/blob/main/SECURITY.md) and [Platforms](https://github.com/admknight/VeylRoute/blob/main/docs/PLATFORMS.md).
