; VeylRoute Windows 3.0.1 installer. Preserves the existing AppId for H5 upgrades.
; Does not bundle Tor, Wintun, lyrebird or tun2socks networking binaries.
[Setup]
AppId={{8BC2FBF6-E0C5-5EF6-9C34-6CBE370151B1}
AppName=VeylRoute Control Center
AppVersion=3.0.1.0
AppVerName=VeylRoute Control Center 3.0.1
AppPublisher=Adam Knight
AppPublisherURL=https://github.com/admknight
AppSupportURL=https://github.com/admknight/VeylRoute/issues
AppUpdatesURL=https://github.com/admknight/VeylRoute/releases/latest
DefaultDirName={autopf}\VeylRoute
DefaultGroupName=VeylRoute
PrivilegesRequired=admin
OutputDir=output
OutputBaseFilename=VeylRoute-Windows-v3.0.1-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\ui\assets\VeylRoute-disconnected.ico
UninstallDisplayIcon={app}\VeylRoute.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableWelcomePage=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "..\VeylRoute.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VeylRoute.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\START-HERE.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VERSION.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README-FIRST.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "install-context-setup.json"; DestDir: "{app}"; DestName: "install-context.json"; Flags: ignoreversion
Source: "..\ui\*"; DestDir: "{app}\ui"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\_internal\*"; DestDir: "{app}\_internal"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\tests\*"; DestDir: "{app}\tests"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\config\*"; DestDir: "{app}\config"; Flags: onlyifdoesntexist uninsneveruninstall recursesubdirs createallsubdirs

[Icons]
Name: "{group}\VeylRoute"; Filename: "{app}\VeylRoute.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\VeylRoute"; Filename: "{app}\VeylRoute.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if FileExists(ExpandConstant('{app}\runtime\session-state.json')) then
    Result := 'An active VeylRoute session may still own Windows routing and DNS settings. Disconnect using the existing installation before updating it.';
end;

function InitializeUninstall(): Boolean;
begin
  Result := not FileExists(ExpandConstant('{app}\runtime\session-state.json'));
  if not Result then
    MsgBox('VeylRoute has an active or incomplete session. Cancel uninstall, run Disconnect or Recovery, and verify restoration first.', mbCriticalError, MB_OK);
end;
