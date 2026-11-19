# VeylRoute for Windows v3.0.0 — Stable release

**Windows x64 · MIT-licensed original code · Unsigned binaries**

This stable publication uses **exactly the same tested H5 binaries** previously published under [v3.0.0-rc1-h5](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0-rc1-h5). The original internal `RC1 H5` names remain in the filenames and GUI to preserve the tested bytes; this is a **release designation change**, not a rebuild or a networking-code change.

## Validation basis

- GitHub Actions [Windows run #3](https://github.com/admknight/VeylRoute/actions/runs/44507797802) passed **31/31** isolated PowerShell 5.1/WPF qualification checks and compiled the portable and setup packages.
- The project owner reported on **November 19, 2026**, that the Windows application had been checked and was working without issues. This is an owner-reported runtime validation, not a new independent remote network test.
- The released assets are copied from the pinned successful Windows build at commit `c34df13aea2c208b2c543205bdc500a79c4e8509`, verified against its SHA-256 checksum file and left byte-identical.

## Downloads

- **Portable ZIP:** `VeylRoute-Windows-v3.0-RC1-H5-Portable.zip` — includes the Windows x64 native launcher.
- **Setup EXE:** `VeylRoute-Windows-v3.0-RC1-H5-Setup.exe` — Windows installer.
- **SHA256SUMS.txt:** verify the downloaded package's integrity.

These remain **unsigned** executables. Windows may display SmartScreen prompts. Tor, Wintun, tun2socks and lyrebird binaries are not bundled; the application uses its separate component-provisioning flow.

## Important technical distinctions

Using VeylRoute and seeing a Tor exit IP does not make Edge or another ordinary browser equivalent to Tor Browser. Local strict-DoH, Wintun, IPv6 and firewall checks alone cannot independently prove every DNS path is leak-free. New Tor circuits also do not guarantee a new external IP. Keep network restoration and safe configuration practices in mind when installing, updating or uninstalling.

## Integrity (same binaries as RC1 H5)

```text
a2d630fb1a07139c12da047d329d233a1f4fec0a59031ace209e948a86a2a34f  VeylRoute-Windows-v3.0-RC1-H5-Portable.zip
c8d17a8f17cf9ed1dabd5432f9ace0319887b36d242caae83e8cafce5e76a6d9  VeylRoute-Windows-v3.0-RC1-H5-Setup.exe
```

Maintained on GitHub by **[Adam Knight (@admknight)](https://github.com/admknight)**. [README](https://github.com/admknight/VeylRoute) · [License](https://github.com/admknight/VeylRoute/blob/main/LICENSE) · [Security](https://github.com/admknight/VeylRoute/blob/main/SECURITY.md).
