# VeylRoute for Linux - foundation only

**Status: NOT IMPLEMENTED / NO LINUX VPN OR TUNNEL BUILD.** Windows v3.0.1 is the only shipped platform. This directory starts an independent Linux engineering lane without modifying the verified Windows routing engine.

## Available now

The `check-environment.sh` script is a **read-only prerequisites probe**. It does not request administrator privileges, install packages, launch Tor, create interfaces, modify routes, configure DNS, or touch firewall rules. It checks for the Linux TUN character device and availability of `ip`, `nft`, `tor`, `tun2socks` and `lyrebird` or `obfs4proxy`; it also detects optional DNS tools `resolvectl` and `nmcli`.

The field `dependencies_present` is only a **binary-presence check**, not evidence of network safety or a usable VPN. The returned `routing_qualified` flag is always `false` until a separate real Linux runtime qualification exists.

To inspect an existing Linux machine:

```sh
bash platforms/linux/check-environment.sh
bash platforms/linux/check-environment.sh --json
bash platforms/linux/tests/test-probe.sh
```

Optional `--require-deps` exits 1 when core prerequisites are missing; it still makes **no network changes**.

## Future platform lifecycle

A Linux implementation must independently support bounded **Preflight → Connect → Status / Health → Disconnect → Recover**, plus Tor **New Circuit** and version-specific updates. Windows WPF, Wintun, Windows DNS/WFP rules and PowerShell routing scripts cannot be reused as though they work on Linux.

Before enabling privileged routing, Linux work must establish a least-privilege permission model, verified Tor/obfs4/tun2socks source installation, native TUN/network/firewall/DNS integration, baseline snapshots and deterministic rollback, DNS and IPv6 containment, kill-switch recovery, cancellation, SelectedAppsOnly isolation, and upgrade/uninstall safety.

This folder's isolated CI tests are not a substitute for those live OS/network tests. Linux, macOS and Android require independent code and release gates. The Windows v3.0.1 source and artifacts remain unchanged.
