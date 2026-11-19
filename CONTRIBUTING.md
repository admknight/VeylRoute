# Contributing

This is a Windows-first Tor routing release candidate. Preserve existing TorTunnel networking, rollback, config defaults and emergency recovery unless a specific reviewed change requires otherwise.

Describe the defect and source evidence, provide a minimal patch, and include a focused regression. Run `tests/Verify-Windows.ps1` on Windows PowerShell 5.1; distinguish static/isolated qualification from live Tor, Wintun, DNS and Windows firewall checks. Do not check in downloaded Tor binaries, private obfs4 bridges, control cookies, local logs, private IP addresses or personal runtime state.

See [release qualification](docs/RELEASE-CHECKLIST.md) and [license status](docs/LICENSE-STATUS.md). Review third-party licenses before incorporating external code.
