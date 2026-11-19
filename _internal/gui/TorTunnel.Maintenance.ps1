# VeylRoute v2.3: reversible root declutter by Hidden attribute, no file moves.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][ValidateSet('Tidy','Untidy')][string]$Action
)
$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($Root)
$manifest = Join-Path $rootPath 'runtime\gui\root-visibility.json'
$folder = Split-Path -Parent $manifest
if (-not (Test-Path -LiteralPath $folder)) { [void](New-Item -ItemType Directory -Path $folder -Force) }
$utf8 = New-Object System.Text.UTF8Encoding($false)
if (Test-Path -LiteralPath (Join-Path $rootPath 'runtime\session-state.json')) {
    throw 'Stop the active TorTunnel session before changing root visibility.'
}
if ($Action -eq 'Tidy') {
    if (Test-Path -LiteralPath $manifest) { throw "A visibility manifest already exists: $manifest. Restore visibility before running Tidy again." }
    $record = @()
    # Scope is only existing, root-level files. Engine paths and file contents stay unchanged.
    foreach ($file in (Get-ChildItem -LiteralPath $rootPath -File -Force -ErrorAction Stop)) {
        if ($file.Name -in @('VeylRoute.vbs','START-HERE.cmd','Emergency-Reset-TorTunnel.cmd','VERSION.txt')) { continue }
        if ($file.Extension -notin @('.ps1','.cmd','.txt')) { continue }
        $record += [pscustomobject]@{ name=$file.Name; originalAttributes=[int]$file.Attributes }
    }
    if ($record.Count -eq 0) { Write-Output 'No support files selected for decluttering.'; exit 0 }
    # Write the manifest BEFORE modifying file attributes so any partial run is recoverable.
    $json = @{ version=1; root=$rootPath; files=@($record) } | ConvertTo-Json -Depth 6
    [IO.File]::WriteAllText($manifest,$json,$utf8)
    foreach ($entry in $record) {
        $path = Join-Path $rootPath $entry.name
        $attr = [IO.File]::GetAttributes($path)
        [IO.File]::SetAttributes($path, ($attr -bor [IO.FileAttributes]::Hidden))
    }
    Write-Output "Root decluttered (hidden attributes): $($record.Count) support files."
    Write-Output 'No scripts were moved or deleted. Tor, tun2socks, config, runtime and emergency reset are untouched.'
    Write-Output 'Windows Explorer configured to show hidden files may still display these files.'
}
else {
    if (-not (Test-Path -LiteralPath $manifest)) { Write-Output 'No visibility manifest. Nothing to restore.'; exit 0 }
    $data = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    if ([int]$data.version -ne 1 -or -not [string]::Equals([IO.Path]::GetFullPath([string]$data.root),$rootPath,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Visibility manifest does not match the current installation. No files changed.'
    }
    $count = 0
    foreach ($entry in $data.files) {
        $name = [string]$entry.name
        if ($name -ne [IO.Path]::GetFileName($name) -or $name -match '[\\/]') { throw "Unsafe file entry in manifest: $name" }
        $path = Join-Path $rootPath $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [IO.File]::SetAttributes($path,[IO.FileAttributes]([int]$entry.originalAttributes))
            $count++
        }
    }
    Remove-Item -LiteralPath $manifest -Force
    Write-Output "Restored original visibility for $count support files."
}
