# VeylRoute for Linux v0.1.0 — Experimental developer build

**Linux x86_64/ARM64 (Python 3.10+) · Debian package and portable archive · Unsigned · NOT a stable privacy VPN release.**

This Linux platform is implemented independently of the stable Windows PowerShell/WPF engine. It is published so maintainers can perform controlled Linux environment tests; **do not assume its routing, privacy and recovery protections are fully qualified on ordinary Linux desktops**.

## Get the packages

- `VeylRoute-Linux-0.1.0-Preview.deb` — Debian/Ubuntu package, root-owned files, CLI launcher, desktop entry and dedicated unprivileged Tor account
- `VeylRoute-Linux-0.1.0-Portable.tar.gz` — source-based portable folder (requires manually running `sudo ./bin/veylroute prepare` for the dedicated Tor user)
- `SHA256SUMS-Linux.txt` — SHA-256 checksums for both packages

**Exact SHA-256 hashes of GitHub CI artifacts:**

```text
d6482b29773533b1cf3eae0311e4c5d9dd66d320b8688f55e4fdce612384fe49  VeylRoute-Linux-0.1.0-Portable.tar.gz
91d2a8b505f9654e16baf02536bb8768be89adb5dd49cb70bab2dbbd84c25b11  VeylRoute-Linux-0.1.0-Preview.deb
```

The source is [platforms/linux](https://github.com/admknight/VeylRoute/tree/main/platforms/linux). Full installation, command-line, bridge and safety information is in the [Linux README](https://github.com/admknight/VeylRoute/blob/main/platforms/linux/README.md).

## Implementation included

- Python CLI for **prepare, preflight, start, cancel, status, health, stop, recover, new-circuit** and a Tk-based graphical control center
- Tor **TransPort and DNSPort** transparent routing; fixed/listed exit country restrictions and optional obfs4 bridge configuration
- Dedicated non-root Tor user with isolated session files; validated control-socket **SAFECOOKIE / NEWNYM**
- nftables application-owned NAT/guard tables, configured in an atomic transaction before bootstrap; cleanup only these app-owned tables
- Read-only route and resolver hash snapshots, cancellation, stopped-process checks and recovery workflow
- No embedded Tor, Wintun, tun2socks or obfs4 third-party executables. No Linux system-wide software installer auto-updater or SelectedAppsOnly at this stage.

## Evidence versus limits

**Verified in GitHub CI:** [Linux run 44585890987](https://github.com/admknight/VeylRoute/actions/runs/44585890987), source commit `9fe4bcb0645b94080d7cf22e1db9700baf321e16`: **14/14 isolated Python tests** passed; shell syntax, prerequisite probe, Linux **kernel nftables install/remove inside a new network namespace**, `dpkg-deb` package contents and hashes passed. The three published assets are the exact CI files, byte-for-byte.

**Not verified:** live Tor bootstrap and actual internet traffic through TransPort, DNS/DoT/DoH/IPv6 leak containment in different Linux resolver configurations, fail-closed behavior under real Tor crashes, active GUI/polkit privilege prompts, upgrades/uninstall and post-fault network recovery on a real user Linux installation. **This is not a general-use verified VPN.**

Do not test system-wide routing on a production host until the [Linux runtime qualification issue](https://github.com/admknight/VeylRoute/issues/1) is closed with evidence. Use an isolated disposable Linux VM for live qualification. Installation alone does not activate routing or firewall rules.

**Windows v3.0.1 remains the repository's latest stable release.** Linux preview has no production stable designation. Original project source is [MIT](https://github.com/admknight/VeylRoute/blob/main/LICENSE); third-party dependencies retain their own licenses. Maintained publicly by [Adam Knight (@admknight)](https://github.com/admknight).
