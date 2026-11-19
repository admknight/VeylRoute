VEYLROUTE WINDOWS BUILD SOURCE (3.0.1 / H6)

On Windows x64, from the complete repository:
  .\tests\VERIFY-WINDOWS.cmd
  .\packaging\BUILD-WINDOWS.ps1
  .\packaging\BUILD-WINDOWS.ps1 -BuildInstaller

Requires Windows PowerShell 5.1, .NET Framework 4.x compiler and Inno Setup
for the installer. Output: VeylRoute.exe and
packaging\output\VeylRoute-Windows-v3.0.1-Setup.exe

Portable ZIP includes install-context.json with installMode=portable.
Setup EXE installs a separate install-context.json with installMode=setup.
The About page checks that marker to choose its update path.

The installer keeps its original AppId for upgrades, preserves config, and
refuses updating or uninstalling when runtime/session-state.json exists.
It does not bundle third-party Tor, Wintun, tun2socks or lyrebird binaries.
The launcher remains a native shell around the PowerShell/WPF GUI.

Do not install or update while connected. Downloaded application releases
must match the GitHub SHA-256 checksum and correct edition. Release tests
require Windows runtime verification; binary compilation alone is not a
network/privacy guarantee. Copyright (c) 2026 Adam Knight. MIT License.
