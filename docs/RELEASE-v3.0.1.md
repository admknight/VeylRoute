# VeylRoute Windows v3.0.1 — Stable

**Windows 10/11 x64 · MIT License · Portable ZIP and Setup EXE · Unsigned**

This release is **the same byte-for-byte v3.0.1 H6 build** previously published as [v3.0.1-rc1](https://github.com/admknight/VeylRoute/releases/tag/v3.0.1-rc1). The project owner explicitly requested promotion to the stable update channel. No Tor engine changes, binary rebuild, installer mutation or package re-signing were performed for this promotion.

## What's new

- The **About VeylRoute** page replaces the identity/version block in the sidebar footer. Public project branding uses **Adam Knight (@admknight)**.
- **Check for updates** detects the newest stable GitHub release and determines whether the installation is **Portable** or **Setup-based**.
- **Download & update** selects the matching Portable ZIP or Setup EXE, verifies its published SHA-256 digest, and requires a disconnected session.
- Portable updates stage and back up application files and have a rollback path; Setup installations use the installer upgrade route.
- Existing Tor component update workflows, TorTunnel v3.5.1 engine scripts and network configuration are not changed by H6.

## Assets

- `VeylRoute-Windows-v3.0.1-Portable.zip`
- `VeylRoute-Windows-v3.0.1-Setup.exe`
- `SHA256SUMS.txt`

Both are **unsigned**. The packages exclude separately provisioned third-party Tor, Wintun, tun2socks and lyrebird binaries.

## Release evidence

- [GitHub Windows qualification and build run](https://github.com/admknight/VeylRoute/actions/runs/44568059908): **37 PASS / 0 FAIL** — Windows PowerShell 5.1 parsing/WPF loading, isolated worker dispatch, updater contract and rollback tests, native x64 launcher and Setup EXE compilation, package checksums.
- The three asset files are copied unchanged from the pinned successful run at commit [cb487027](https://github.com/admknight/VeylRoute/commit/cb487027cf34c2bb7761aa686bb042b8e1e20795).
- **Project-owner decision:** promote the qualified H6 binary to **stable** and continue the development pipeline. This is a release policy decision; it does not mean a separate independent full live update test occurred.

## SHA-256

```text
3479a3e6e3e3b8f8fd8782a6b4d8b9ae4adcd7b2d94b73e497997f19d8e70134  VeylRoute-Windows-v3.0.1-Portable.zip
3dd8cc7f5e66cab23f22f4da73a79378374eeafc482e28d5bfbfaec7f6098e86  VeylRoute-Windows-v3.0.1-Setup.exe
```

## Safety and scope

Do not update while a Tor routing session is active. A successful exit-IP test or enabled DoH/firewall rules alone is not a general guarantee of anonymity or absence of DNS leaks. The updated installer retains the existing upgrade AppId, and the application checks the latest **stable** release only. Automatic self-update and error recovery in the user's live Windows environment are not independently demonstrated by the CI results.

Maintained publicly by [Adam Knight (@admknight)](https://github.com/admknight). Original VeylRoute code is [MIT-licensed](https://github.com/admknight/VeylRoute/blob/main/LICENSE); third-party components retain their own licenses.
