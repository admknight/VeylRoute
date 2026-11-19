VEYLROUTE CONTROL CENTER v3.0.1
Creator: Adam Knight (c) 2026
Engine: TorTunnel Universal v3.5.1, unchanged network/routing scripts

PORTABLE FIRST RUN (Windows 10/11 x64, administrator approval required)

1. Extract this COMPLETE package to a writable LOCAL folder on any drive
   (for example D:\Apps\VeylRoute). Do not extract over an active installation.
   Avoid network shares; do not move the folder while a tunnel session is active.
2. Double-click VeylRoute.vbs and approve UAC. No other application installer
   is required. Windows PowerShell 5.1 and WPF are used as shipped in Windows.
3. The welcome guide and Versions & updates page identify missing components.
   Use the built-in action to download/verify Wintun + tun2socks, or import a
   trusted local binary folder. Importing is NOT independent authenticity proof.
4. Use Download + verify signature for the Tor Windows x64 Expert Bundle.
   VeylRoute downloads and verifies Tor + lyrebird + GeoIP and installs only
   after explicit approval. The internal OpenPGP library is downloaded into
   this app on first use; no Gpg4win installer is needed. HTTPS to Tor Project,
   NuGet and the pinned public-key service may be required on first setup.
   If blocked, Import signed bundle accepts a matching archive, .asc signature,
   and signing key; signature checks remain mandatory.
5. If obfs4 bridges are missing, use the Get obfs4 bridges link and paste the
   full bridge lines. Validate format, then Save. Format validation is not proof
   of network reachability. Do not publish or share private bridge lines.
6. Choose SystemWide or SelectedAppsOnly, configure DNS/exit/app settings,
   Save, run Preflight, then Connect. Confirm with a full Health Check.
7. Minimize/close hides the GUI in the tray. To disconnect the tunnel use the
   Disconnect control; Exit GUI intentionally leaves an active tunnel running.

UPGRADING A CURRENT VEYLROUTE INSTALLATION

Fully stop the tunnel, exit the GUI and back up the entire current folder.
Extract this package separately. Replace ONLY these changed application files:
  _internal\gui\TorTunnel.GuiWorker.ps1
  _internal\gui\TorTunnel.PackageUpdater.ps1
  ui\TorTunnel.ModernGui.ps1
  ui\TorTunnel.ModernGui.xaml
Do not overwrite existing config, runtime, Tor or tun2socks folders. The
optional Windows qualification tests are under tests\VERIFY-WINDOWS.cmd.

EMERGENCY ACCESS

START-HERE.cmd retains the original console-based control/recovery path.
The networking engine scripts remain under _internal. Never remove runtime
session-state files manually while network routing/kill-switch rules are live.

RELEASE STATUS

This is a Windows RELEASE CANDIDATE, not a production-verified release.
Source, archive and isolated fixture tests were performed in the authoring
container. Actual Windows PowerShell 5.1, WPF, component installation,
Wintun/WFP, DNS/leak protection, Tor connectivity and rollback require a
live Windows qualification pass. Website/domain-specific bypass is not
implemented. See docs\WINDOWS-QUALIFICATION.txt.
