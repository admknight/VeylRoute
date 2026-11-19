# Import the exact Windows H5 source baseline into a fresh VeylRoute Git clone.
# No git commit/push, software installation, Tor startup or live routing.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceZip)
$ErrorActionPreference = 'Stop'
$expectedHash = '81ADB12079247FB4C46FB1963D716842B9C96922424AC4A62E845807840E0493'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) { throw 'Run this script from a cloned Git repository.' }
$zipPath = [IO.Path]::GetFullPath($SourceZip)
if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw 'Full H5 candidate ZIP was not found.' }
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($hash -ne $expectedHash) { throw "Unexpected source ZIP SHA256: $hash" }
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$prefix = 'VeylRoute-Windows-v3.0-RC1/'
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
$created = New-Object 'System.Collections.Generic.List[string]'
try {
    $files = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $archive.Entries) {
        if (-not $entry.FullName.StartsWith($prefix, [StringComparison]::Ordinal)) { throw ('Unexpected ZIP root: '+$entry.FullName) }
        $rel = $entry.FullName.Substring($prefix.Length)
        if (-not $rel -or $rel.EndsWith('/')) { continue }
        $parts = $rel.Split('/')
        if ($parts -contains '..' -or $parts -contains '.' -or [IO.Path]::IsPathRooted($rel)) { throw ('Unsafe archive entry: '+$rel) }
        $dest = [IO.Path]::GetFullPath((Join-Path $repo ($rel.Replace('/','\'))))
        if (-not $dest.StartsWith(($repo.TrimEnd('\')+'\'), [StringComparison]::OrdinalIgnoreCase)) { throw ('Entry outside repository: '+$rel) }
        if (Test-Path -LiteralPath $dest) { throw ('Import refuses to overwrite: '+$rel) }
        $files.Add([pscustomobject]@{Entry=$entry;Dest=$dest;Relative=$rel})
    }
    $bridge = $files | Where-Object { $_.Relative -eq 'config/bridges.txt' } | Select-Object -First 1
    if (-not $bridge -or $bridge.Entry.Length -ne 0) { throw 'Public config/bridges.txt must exist and be empty.' }
    foreach ($file in $files) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $file.Dest)) | Out-Null
        $inputStream = $file.Entry.Open()
        try {
            $outputStream = [IO.File]::Open($file.Dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            $created.Add($file.Dest)
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
    }
    Write-Host ('Imported '+$created.Count+' H5 source files. No commit or push performed.') -ForegroundColor Green
    Write-Host 'Review public contact details, git status and changes before committing.'
} catch {
    foreach ($file in $created) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    throw
} finally { $archive.Dispose() }
