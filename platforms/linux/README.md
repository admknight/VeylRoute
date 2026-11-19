# VeylRoute for Linux — experimental application (v0.1.0)

**Status: implementation candidate, not a production-qualified VPN.** Independent of the shipped **Windows v3.0.1 stable** implementation. The app offers a Python 3 CLI, desktop GUI, opt-in privileged system-wide Tor/Tor-DNS transparent routing, obfs4 bridge configuration, exit-country preference, Health, New Circuit, cooperative Cancel, Stop and Recover. It **does not** use Wintun or require tun2socks on Linux; Tor's native transparent proxy and `nftables` handle locally originated TCP and UDP/53. Other UDP is blocked.

The source, tests and CI package build can be used now. **End-to-end Linux machine validation is still required before this can be called privacy-safe or a stable release.** No code signing, auto-update, SelectedAppsOnly isolation, Linux AppImage, or multiple distro certification is claimed.

## Installation

Debian/Ubuntu with Linux nftables support, Python >=3.10, `tor`, `nftables`, `iproute2` and standard `adduser`:

```bash
# Install a build downloaded from a trusted GitHub Actions run after checking SHA256SUMS-Linux.txt
sudo apt install ./VeylRoute-Linux-0.1.0-Preview.deb
# GUI (Tkinter and polkit agent recommended):
veylroute-gui
# or terminal (explicit elevation):
sudo veylroute preflight
```

The Debian installer creates a dedicated unprivileged `veylroute-tor` service account and a private Tor data directory. It **does not** launch Tor, alter firewall rules or enable a background service merely by installing. Existing Tor installations are not changed; VeylRoute uses its own listening ports and Tor data directory. Optional `obfs4proxy` or `lyrebird` is required only if using obfs4 bridges; no private bridges are bundled.

For the source-only portable tarball, extract then explicitly prepare the service account:

```bash
cd veylroute-linux-0.1.0
sudo ./bin/veylroute prepare
sudo ./bin/veylroute preflight
./bin/veylroute-gui
```

**Portable caveat:** running privileged Python source from a user-writable directory is not equivalent to an installed, root-owned package. For actual testing prefer the Debian package or a protected root-owned directory, verify its origin, and do not run source from an untrusted location.

## Main operations

```bash
sudo veylroute prepare                     # only required for portable installation
sudo veylroute preflight                  # no network changes
sudo veylroute start --exit-country US    # applies fail-closed nft rules *before* Tor bootstrap
veylroute status                          # read-only public summary, not independent verification
sudo veylroute health                     # local Tor process and firewall rule health
sudo veylroute new-circuit                # authenticated Tor SAFECOOKIE / NEWNYM
sudo veylroute stop                       # stop managed Tor, remove only VeylRoute nft tables
sudo veylroute recover                    # recover interrupted start / stale state
```

To use private obfs4 bridge entries, prepare a private file (do not commit to Git or publish it) with lines of the form `obfs4 IPv4:port fingerprint cert=... iat-mode=0`. Invoke `start --bridges-file /path/to/private.txt`. Other transports and IPv6 bridge rows are **not** supported by this preview.

During a stalled bootstrap, use `sudo veylroute cancel` from a second terminal, or press **Cancel** in the GUI. This sets a cooperative flag. On a normal expected failure, VeylRoute terminates its Tor process, removes only its own nft tables and reports disconnected. If rollback fails, firewall rules **remain fail-closed** and the status indicates `recovery-required`.

## Architecture and protections

VeylRoute Linux uses two namespaced `nftables` tables (`ip veylroute_nat`, `inet veylroute_guard`) in one transaction, with a dedicated Tor process UID permitted to make the bridge/directory connections. Other local IPv4 TCP goes through Tor's `TransPort`, UDP/53 through Tor's `DNSPort`, local loopback stays local, IPv6/non-DNS UDP and other non-Tor egress are dropped; broadcast DHCPv4 is exempt. The rules are installed **before** Tor bootstrap. No existing nft rules are flushed, and no default routes, `/etc/resolv.conf`, NetworkManager profile or DNS settings are rewritten. A read-only snapshot records IPv4/IPv6 routes and resolver hash for post-session comparison.

The operating system and upstream software impose limits: this cannot guarantee DNS-leak freedom on all distributions; applications using local proxies or nonstandard kernel bypasses are outside the current containment model, existing firewall rules can conflict, and some DHCPv4 renewals and IPv6 network control traffic may be affected. Tor `DNSPort` handles a limited set of DNS query types. The Linux program does not persist fail-closed state across a reboot; after reboot, no active session means the underlying normal network is restored. Browser fingerprinting protections of Tor Browser are **not** provided.

**Privileges:** GUI runs as the current user. Admin actions invoke the packaged root-owned CLI via `pkexec` and the user's polkit agent; the CLI is also accessible through explicit `sudo`. Tor itself runs under the dedicated non-root UID. The Tor cookie and bridge configuration remain private.

## Building / checks

```bash
PYTHONPATH=platforms/linux python3 -m unittest discover -s platforms/linux/tests -p 'test_*.py' -v
bash platforms/linux/tests/test-probe.sh
bash platforms/linux/packaging/build-linux.sh dist
# Read-only environment probe (legacy foundational check)
bash platforms/linux/check-environment.sh --json
```

CI provides contract tests and unsigned `.deb` plus portable `.tar.gz` with SHA-256 checksums. CI does **not** alter the runner's live routes or firewall. An optional isolated network-namespace nft syntax/install/cleanup probe never changes the host's network stack.

## Release gate — still open

- Native Linux distribution validation (Debian/Ubuntu; laptop, Wi-Fi, ethernet and container/hypervisor differences)
- Real Tor bootstrap through direct and obfs4 bridges and different exit locations
- DNS, DoH, DoT and IPv6 egress verification on a controlled Linux VM, including failure conditions
- Kill-switch behavior during bootstrap/after Tor crashes; explicit cancellation and deterministic rollback
- Package installation, upgrade, active-session uninstall refusal, desktop polkit GUI and recovery under real faults
- SelectedAppsOnly routing, Linux update channel and wider distro support — separate work, not silently claimed as implemented

Windows v3.0.1 remains the latest **stable** platform release. This Linux edition is **not** ready for general deployment until these gates have observable results.

Upstream references: [Tor TransPort/DNSPort](https://man.archlinux.org/man/tor.1.en), [Tor SAFECOOKIE/NEWNYM](https://spec.torproject.org/control-spec/commands.html), [nftables NAT and redirect](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_%28NAT%29).
