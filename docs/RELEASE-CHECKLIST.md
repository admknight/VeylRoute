# Windows release acceptance

**Current state:** Windows v3.0 RC1 H5 **unsigned prerelease** — [download](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0-rc1-h5). The code baseline compiled was `c34df13aea2c208b2c543205bdc500a79c4e8509`.

## Checks supported by observed evidence

- [x] Full H5 source imported and 83 source file hashes reconciled
- [x] MIT License selected and retained with source and compiled package payloads
- [x] H5 Windows PowerShell 5.1/WPF isolated qualification **31 PASS / 0 FAIL** — [Run #3](https://github.com/admknight/VeylRoute/actions/runs/44507797802)
- [x] Native x64 launcher **compiled** on GitHub's Windows runner
- [x] Inno Setup EXE **compiled** on GitHub's Windows runner
- [x] Portable ZIP includes launcher, MIT License and empty public bridges config
- [x] Windows build artifacts SHA-256 checksums verified and included in [prerelease](https://github.com/admknight/VeylRoute/releases/tag/v3.0.0-rc1-h5)
- [x] Third-party networking binaries **excluded** from the public repository and packages

## Remaining before production qualification

- [ ] Native EXE GUI launch, UAC approval/cancellation and error handling tested on a Windows user desktop
- [ ] Portable package runs correctly with writable runtime data in real use
- [ ] Setup EXE install, repair/upgrade, uninstall and session-state protection tested on Windows
- [ ] First-run Tor / lyrebird, Wintun and tun2socks signed/source-verified provisioning tested
- [ ] SystemWide connect, Tor identity, Health and **independent** post-Disconnect network restoration demonstrated for H5
- [ ] SelectedAppsOnly mode and fail-closed protected-app routing demonstrated
- [ ] Cancellation during stalled bootstrap, log streaming and recovery demonstrated
- [ ] SAFECOOKIE / New Circuit live request and exit-IP comparison demonstrated
- [ ] DNS traffic-path containment and fail-closed behavior independently tested
- [ ] IPv6, DNS, firewall, Edge policy restore and repeat sessions demonstrated
- [ ] Package signing/authenticity strategy established for a production distribution
- [ ] Upstream license review completed **before** any future bundling of third-party binaries

**Release gate:** GitHub compilation and isolated tests justify an **unsigned prerelease**, not a production or leak-free claim. Exit-country listings require current Tor relay evidence; PK availability is not guaranteed by its ISO country code.
