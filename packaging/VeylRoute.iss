; VeylRoute H5 - compile with Inno Setup on Windows after building VeylRoute.exe.
; This packages application scripts and native launcher; it does NOT bundle Tor/Wintun/tun2socks.
; Keep existing settings and never replace an active networking session.
[Setup]
AppId={{8BC2FBF6-E0C5-5EF6-9C34-6CBE370151B1}
AppName=VeylRoute Control Center
AppVersion=3.0.0.5
AppVerName=VeylRoute Control Center 3.0 RC1 H5
AppPublisher=Scopewise Consulting
DefaultDirName={autopf}\VeylRoute
DefaultGroupName=VeylRoute
PrivilegesRequired=admin
OutputDir=output
OutputBaseFilename=VeylRoute-Windows-v3.0-RC1-H5-Setup
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
