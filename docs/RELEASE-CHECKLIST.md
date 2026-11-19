# Windows release and verification record

**Release:** [VeylRoute for Windows v3.0.0 — stable](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0). **Binary baseline:** unchanged RC1 H5 build, commit `c34df13aea2c208b2c543205bdc500a79c4e8509`. **Distribution:** unsigned portable ZIP and Setup EXE, with MIT License and SHA-256 checksums.

## Source and CI evidence — directly observed

- [x] Full H5 source published and 83 source file hashes reconciled
- [x] Original VeylRoute code distributed under the MIT License, with historical rights-holder attribution preserved
- [x] H5 Windows PowerShell 5.1/WPF isolated qualification **31 PASS / 0 FAIL** — [GitHub Actions run #3](https://github.com/admknight/VeylRoute/actions/runs/44507797802)
- [x] Native x64 launcher and Inno Setup EXE compiled successfully on GitHub's Windows runner
- [x] Portable ZIP contents, empty public bridge configuration and SHA-256 checksums verified
- [x] Stable release asset digests match the earlier H5 prerelease byte-for-byte
- [x] Third-party networking binaries are not bundled

## Runtime evidence — project owner confirmation

On **November 19, 2026**, the project owner reported: **“everything is checked and working actually, without any issue.”** This confirmation is the basis for the requested stable-release designation. It is **owner-reported acceptance**, not a substitute for an independently retained test log covering every failure mode.

The reported acceptance concerns the Windows application and its tested functionality, including connection/disconnection, status dialogs, Overview privacy indicators, and other H5 operations. No new implementation or new Windows executable was created for the stable tag. The stable edition intentionally retains the H5 binary filenames and the same checksums.

## Continuing distribution and security considerations

- The packages remain **unsigned**; Windows SmartScreen may display warnings.
- Tor, lyrebird, Wintun and tun2socks must be provisioned separately, under their respective licenses.
- Tor exit-IP verification does not make an ordinary browser equivalent to Tor Browser.
- A local DoH setting, firewall rule or exit-IP check cannot establish a universal guarantee that DNS or other traffic can never leak under every condition.
- Avoid upgrading or uninstalling while the application has an active routing session.

The earlier [RC1 H5 prerelease](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0-rc1-h5) is retained for traceability. Future platform releases (Linux, macOS and Android) require separate implementations and qualification.
