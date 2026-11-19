# Windows release acceptance

**Baseline:** v3.0 RC1 H5 candidate. The H4 isolated Windows qualification previously passed 26/26 in a user-run test. H5, binaries and privacy paths require independent checks.

- [ ] H5 isolated Windows PowerShell/WPF qualification passes on GitHub Actions; commit and runner identified
- [ ] Native EXE builds and launches GUI; UAC approval/cancellation handled
- [ ] Portable ZIP launches and preserves independent, writable runtime data
- [ ] Setup EXE installs, upgrades, and uninstalls safely with session-state protection
- [ ] Tor / lyrebird, Wintun, tun2socks installation/provisioning verifies its upstream sources
- [ ] SystemWide connection, Tor identity check, Health and independent post-Disconnect restoration pass
- [ ] SelectedAppsOnly routing and protected-app behavior pass
- [ ] Connection cancellation, timeouts and log streaming complete without misleading success/failure
- [ ] SAFECOOKIE / manual NEWNYM live check correctly distinguishes request acknowledgement from a changed public IP
- [ ] DNS traffic path containment and fail-closed behavior are independently tested
- [ ] IPv6 behavior, firewall controls, recovery and repeat connection pass
- [ ] Third-party license/redistribution review and source copyright/license decision complete
- [ ] Artifact SHA-256 integrity, release notes and authenticity/signing decision documented

Passing GitHub Actions alone permits only **unsigned qualification artifacts**, not a production release. Do not infer that Pakistan has a working exit solely from its ISO country code; use fresh Tor relay information and separate bootstrap diagnosis.
