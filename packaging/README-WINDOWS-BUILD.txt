VEYLROUTE WINDOWS BUILD SOURCE (H5)

The source package is portable, not a compiled EXE. On Windows x64:
1. Disconnect any VeylRoute session, and exit the GUI.
2. Open Windows PowerShell 5.1 in this extracted folder.
3. To create a native launcher EXE:
       .\packaging\BUILD-WINDOWS.ps1
   This uses the Windows .NET Framework 4.x csc.exe compiler and builds
   VeylRoute.exe into the extracted package folder.
4. To create a conventional setup EXE, install Inno Setup 6 from
   https://jrsoftware.org/isinfo.php and run:
       .\packaging\BUILD-WINDOWS.ps1 -BuildInstaller
   Expected setup output:
       packaging\output\VeylRoute-Windows-v3.0-RC1-H5-Setup.exe
5. Verify SHA256 hashes and run the Windows qualification suite.

The launcher is a windowless native EXE that starts the EXISTING WPF
PowerShell application with elevation. It is not a conversion of PowerShell
into a standalone native implementation. Windows PowerShell 5.1 remains
required on the target PC.

The installer is admin-elevated and installs under Program Files. It does NOT
migrate the existing portable folder. It installs only app source, GUI and
shortcuts, not third-party Tor, tun2socks or Wintun binaries. Those must be
provisioned using the existing source-verifying VeylRoute component workflow.

Do not run Setup over a connected/partially restored installation. It refuses
when its destination still has runtime/session-state.json. Uninstall also
refuses with an active session state and retains runtime/config data.

The produced binaries are unsigned until a legitimate signing certificate is
used. On Windows, test UAC cancellation, first launch, elevated launcher,
first-run component setup, upgrade/downgrade, stop, uninstall and recovery.
Never claim full release qualification from a successful EXE compilation alone.
