# Copyright (c) 2026 Zahid Hussain / Scopewise Consulting.
# Build a native EXE launcher on Windows x64 and optionally compile an Inno Setup EXE.
# No network operations, Tor startup, binary downloads or routing changes.
[CmdletBinding()]
param([switch]$BuildInstaller)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem){throw 'Build on 64-bit Windows.'}
if(Test-Path -LiteralPath (Join-Path $root 'runtime\session-state.json') -PathType Leaf){
    throw 'Disconnect VeylRoute before building or replacing launcher files.'
}
foreach($rel in @('ui\TorTunnel.ModernGui.ps1','ui\TorTunnel.ModernGui.xaml','ui\assets\VeylRoute-disconnected.ico')){
    if(-not(Test-Path -LiteralPath (Join-Path $root $rel) -PathType Leaf)){throw ('Missing source file: '+$rel)}
}
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(-not(Test-Path -LiteralPath $csc -PathType Leaf)){throw 'The .NET Framework C# command-line compiler was not found.'}
$source=Join-Path $PSScriptRoot 'VeylRouteLauncher.cs'
$icon=Join-Path $root 'ui\assets\VeylRoute-disconnected.ico'
$out=Join-Path $root 'VeylRoute.exe'
& $csc '/nologo' '/target:winexe' '/platform:x64' '/optimize+' '/reference:System.Windows.Forms.dll' ('/win32icon:'+ $icon) ('/out:'+ $out) $source
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $out -PathType Leaf)){throw 'Native EXE compilation failed; no installer was built.'}
Write-Host ('Native EXE created: '+$out) -ForegroundColor Green
Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash)
if(-not $BuildInstaller){Write-Host 'EXE-only build completed. Use -BuildInstaller to compile a setup EXE with Inno Setup.';exit 0}
$possible=@(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 7\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 7\ISCC.exe')
)
$iscc=$possible|Where-Object{$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}|Select-Object -First 1
if(-not $iscc){
    $tool=Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if($tool){$iscc=$tool.Source}
}
if(-not $iscc){throw 'The native launcher was built, but Inno Setup ISCC.exe is not installed. Obtain Inno Setup from jrsoftware.org to build setup.exe.'}
$iss=Join-Path $PSScriptRoot 'VeylRoute.iss'
& $iscc $iss
if($LASTEXITCODE -ne 0){throw 'Inno Setup compilation failed.'}
$setup=Join-Path $PSScriptRoot 'output\VeylRoute-Windows-v3.0-RC1-H5-Setup.exe'
if(-not(Test-Path -LiteralPath $setup -PathType Leaf)){throw 'Compiler reported success but setup.exe is missing.'}
Write-Host ('Installer created: '+$setup) -ForegroundColor Green
Write-Host ('SHA256: '+(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash)
Write-Warning 'Unsigned RC installer candidate: verify on a disposable Windows machine and sign before public release.'
