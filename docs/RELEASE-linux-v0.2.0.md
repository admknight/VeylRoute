# VeylRoute Linux v0.2.0 — Experimental desktop & feature-parity build

**Linux (Debian/Ubuntu packaging) · MIT License · unsigned preview — not a stable VPN/privacy-qualified release.**

This release extends [v0.1.0](https://github.com/admknight/VeylRoute/releases/tag/linux-v0.1.0-experimental). Windows [v3.0.1 stable](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1) remains unchanged and stays GitHub's recommended Latest version.

## New in 0.2.0

- **VeylRoute application icon** for menus, taskbar/dock grouping and window decoration; state-specific connecting, connected, disconnected and warning assets derived directly from the approved Windows artwork
- **Debian desktop entry:** registered application-menu entry with `Icon=veylroute`, `StartupWMClass=Veylroute`, and installed hicolor icon assets
- **Portable desktop integration:** explicit install/remove user-level XDG menu shortcut; nothing is automatically pinned to a dock
- **Optional system tray:** available through supported Ayatana AppIndicator or pystray/Pillow integrations with status icons and limited safe controls; visibility varies by Linux desktop and extension support
- **Expanded GUI:** 11 pages for Overview, exits, DNS, app routing status, obfs4 bridges, preferences, activity, Tor/component maintenance, app updates and About
- **Saved UI preferences** without storing bridge secrets
- **Linux-specific application update path:** checks matching *stable Linux* GitHub releases, not Windows Latest or experimental tags; selects Debian vs portable package, verifies SHA256SUMS and published asset digest, refuses active sessions, then uses package manager or portable backed-up file replacement with rollback

The previous Linux Tor controller, SAFECOOKIE/NEWNYM integration, cancellation and dedicated nftables model remain the platform foundation. **SelectedAppsOnly is explicitly *not* implemented**: Linux requires a separately validated isolation model rather than Windows Wintun semantics.

## Downloads and integrity

- `VeylRoute-Linux-0.2.0-Preview.deb`
- `VeylRoute-Linux-0.2.0-Portable.tar.gz`
- `SHA256SUMS-Linux.txt`

```text
97ed7b45b078dcaa67e173e7850043d9d81a0168e4bd8931df7243e59c7daffd  VeylRoute-Linux-0.2.0-Portable.tar.gz
d224ff340edbcb6eda2ac019b7b051cbce8ab6a3aa58b645053411558a2fe2e2  VeylRoute-Linux-0.2.0-Preview.deb
```

The assets come **unchanged** from the successful [GitHub Linux build run](https://github.com/admknight/VeylRoute/actions/runs/44593706249) at merge commit `5b82665d65228354da132419913bbe8faa62b3e7`. Its isolated qualification passed **26/26** Python tests, XDG desktop entry validation, headless Tk navigation smoke tests for **11 pages**, kernel nftables install/remove in a disposable network namespace, and package/hash inspection. This is CI/package evidence, **not** a real-world networking/privacy certification.

## Important limits before live use

**Not independently verified on a representative Linux installation:** successful Tor bootstrap, IPv4/IPv6 traffic and DNS/DoT/DoH containment, full fail-closed behavior under real Tor crashes or recovery, real desktop/polkit and tray behavior, live Debian/portable self-update, installer upgrade/uninstall, and recovery of ordinary networking after all failure modes. Linux auto-updates intentionally ignore this preview until a later **stable Linux release** exists.

Use a **disposable Linux VM** for routing and failure experiments. Installing the Debian package alone does not activate routing. The portable archive should not be run as privileged Python code from untrusted/user-writable locations. No code signing is included. The GUI may function without a tray depending on your environment.

- [Linux installation and operations](https://github.com/admknight/VeylRoute/blob/main/platforms/linux/README.md)
- [Source, tests and icon provenance](https://github.com/admknight/VeylRoute/tree/main/platforms/linux)
- [Outstanding live runtime gate](https://github.com/admknight/VeylRoute/issues/1)
- [Feature parity PR #2](https://github.com/admknight/VeylRoute/pull/2)

Maintained publicly by **Adam Knight (@admknight)**. Original project source is MIT-licensed; external Tor/networking components retain their own terms.
