# Windows release and verification record

**Release:** [VeylRoute for Windows v3.0.1 — stable](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1). **Binary baseline:** unchanged H6 build, commit `cb487027cf34c2bb7761aa686bb042b8e1e20795`. **Distribution:** unsigned portable ZIP and Setup EXE, with MIT License and SHA-256 checksums.

## Source and CI evidence — directly observed

- [x] H6 source published with its source manifest validated by Windows CI.
- [x] Original VeylRoute code distributed under the MIT License, with historical rights-holder attribution preserved
- [x] H6 Windows PowerShell 5.1/WPF isolated qualification **37 PASS / 0 FAIL** — [GitHub Actions](https://github.com/admknight/VeylRoute/actions/runs/44568059908)
- [x] Native x64 launcher and Inno Setup EXE compiled successfully on GitHub's Windows runner
- [x] Portable ZIP contents, empty public bridge configuration and SHA-256 checksums verified
- [x] Stable release asset digests match v3.0.1-rc1 byte-for-byte
- [x] Third-party networking binaries are not bundled

## Runtime and promotion evidence

The project owner confirmed successful testing for the earlier v3.0.0 H5 baseline. On November 19, 2026, the project owner explicitly authorized promotion of the H6 binaries to stable, without changing the app source or rebuilding them. **The new portable and Setup self-update paths have not been independently retested in the user environment in the available evidence.** Stable is the owner's release designation, not proof of universal DNS privacy or error-free updates.

## Continuing distribution and security considerations

- The packages remain **unsigned**; Windows SmartScreen may display warnings.
- Tor, lyrebird, Wintun and tun2socks must be provisioned separately, under their respective licenses.
- Tor exit-IP verification does not make an ordinary browser equivalent to Tor Browser.
- A local DoH setting, firewall rule or exit-IP check cannot establish a universal guarantee that DNS or other traffic can never leak under every condition.
- Avoid upgrading or uninstalling while the application has an active routing session.

The earlier [H6 RC prerelease](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1-rc1) is retained for traceability. Future platform releases (Linux, macOS and Android) require separate implementations and qualification.
