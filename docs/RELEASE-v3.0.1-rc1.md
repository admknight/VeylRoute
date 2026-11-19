# VeylRoute Windows v3.0.1 H6 — About & Smart Updates

**Unsigned release candidate / preview.** The prior [v3.0.0 stable release](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0) is unchanged.

Built on GitHub Actions from commit [cb487027](https://github.com/admknight/VeylRoute/commit/cb487027cf34c2bb7761aa686bb042b8e1e20795). [Windows qualification & build evidence](https://github.com/admknight/VeylRoute/actions/runs/44568059908): **37 PASSED / 0 FAILED** on Windows PowerShell 5.1/WPF, native launcher compiled, Inno Setup compiled, and both unsigned artifacts packaged.

## New in v3.0.1

- A dedicated **About VeylRoute** page replaces public developer/copyright text in the sidebar footer. Displays application version, platform/engine, **Adam Knight (@admknight)** developer credit, open-source notices and release links.
- **Check for updates** and **Download & update** use the GitHub **latest stable** release; no development/prerelease binaries are offered through the in-app stable update channel.
- An explicit installation-context marker selects **portable ZIP** or **Setup EXE**. Older versions without a marker use a conservative compatibility check and refuse uncertain Program Files updates.
- Update staging verifies published **SHA-256** checksums and GitHub digest metadata where available. Downloading or checking does not change the running application or network settings.
- Applying an update requires VeylRoute to be **disconnected**. The helper waits for the GUI to exit, then uses the existing Setup installer or a backed-up portable app-files replacement with rollback. Existing configuration, Tor binaries, tun2socks and runtime session data are not intentionally overwritten.
- The detailed **Versions & updates** area remains for the **Tor component updater**; About handles VeylRoute application updates.
- Public current-source app, publisher and docs identity is **Adam Knight**. Older Git history and v3.0.0 binaries remain historical records; source attribution changes do not delete them.

## Downloads

- **Portable ZIP:** `VeylRoute-Windows-v3.0.1-Portable.zip`
- **Setup EXE:** `VeylRoute-Windows-v3.0.1-Setup.exe`
- **SHA256SUMS.txt**: verify integrity before trying either unsigned package

## Verification boundary

**Observed in GitHub CI:** all 37 isolated Windows checks passed; PowerShell native parser and WPF XAML loading, worker dispatch, install-mode marker, updater guards, source manifest, portable rollback contract, and package compilation. The portable archive was independently inspected for its MIT license, edition marker, version, required executable and updater files, and absence of the previous private-name strings; SHA-256 checksums matched.

**Not yet demonstrated on the user's PC:** live UI interaction in the About page, downloading from GitHub with your real network configuration, a working portable self-update and rollback under fault, or a Setup upgrade including installer/UAC behavior. A checked SHA-256 receipt is **not** proof of safe execution on every machine. In particular, please test updates while disconnected and verify you can restart normally.

**Unsigned build:** Windows SmartScreen may warn. Tor and other third-party network binaries are not bundled. Privacy/DoH/fail-closed protections remain a separate runtime assurance question; this H6 candidate has **not** changed Tor's routing-engine scripts.

## SHA-256

```text
3479a3e6e3e3b8f8fd8782a6b4d8b9ae4adcd7b2d94b73e497997f19d8e70134  VeylRoute-Windows-v3.0.1-Portable.zip
3dd8cc7f5e66cab23f22f4da73a79378374eeafc482e28d5bfbfaec7f6098e86  VeylRoute-Windows-v3.0.1-Setup.exe
```

Maintained publicly by [Adam Knight (@admknight)](https://github.com/admknight) · [MIT license](https://github.com/admknight/VeylRoute/blob/main/LICENSE) · [Repository](https://github.com/admknight/VeylRoute).
