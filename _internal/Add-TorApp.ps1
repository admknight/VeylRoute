[CmdletBinding()]
param([switch]$PauseAtEnd, [string]$Root)

$ErrorActionPreference = 'Stop'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
$ListPath = Join-Path $Root 'config\tor-apps.txt'

try {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Choose an application that should use Tor in SelectedAppsOnly mode'
    $dialog.Filter = 'Applications (*.exe)|*.exe|All files (*.*)|*.*'
    $dialog.Multiselect = $false
    $dialog.CheckFileExists = $true
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { exit 0 }

    $selected = [IO.Path]::GetFullPath($dialog.FileName)
    $name = [IO.Path]::GetFileName($selected)
    if ($name -ieq 'tor.exe' -or $name -ieq 'tun2socks.exe' -or $name -ieq 'curl.exe') {
        throw "$name cannot be placed in tor-apps.txt because TorTunnel uses it for transport/health checks."
    }

    if (-not (Test-Path -LiteralPath (Split-Path $ListPath))) { New-Item -ItemType Directory -Path (Split-Path $ListPath) -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $ListPath)) {
        @('# Applications below use Tor only when SelectedAppsOnly is chosen at Start.') | Set-Content -LiteralPath $ListPath -Encoding UTF8
    }

    $existing = @()
    foreach ($line in @(Get-Content -LiteralPath $ListPath -ErrorAction SilentlyContinue)) {
        $t = [string]$line
        if (-not $t) { continue }
        $t = $t.Trim().Trim('"')
        if (-not $t -or $t.StartsWith('#')) { continue }
        $t = [Environment]::ExpandEnvironmentVariables($t)
        if (-not [IO.Path]::IsPathRooted($t)) { $t = Join-Path $Root $t }
        try { $existing += [IO.Path]::GetFullPath($t) } catch {}
    }

    if ($existing | Where-Object { [string]::Equals($_,$selected,[StringComparison]::OrdinalIgnoreCase) }) {
        Write-Host "$selected is already in the TOR-app list." -ForegroundColor Yellow
    }
    else {
        Add-Content -LiteralPath $ListPath -Value ('"' + $selected + '"') -Encoding UTF8
        Write-Host 'Added TOR-only app:' -ForegroundColor Green
        Write-Host "  $selected"
    }

    if (Test-Path -LiteralPath (Join-Path $Root 'runtime\session-state.json')) {
        Write-Warning 'TorTunnel is currently connected. The edited list takes effect after Stop, then Start again.'
    } else { Write-Host 'It will take effect on the next Start-TorTunnel.' }
}
catch {
    Write-Host "Could not add TOR app: $($_.Exception.Message)" -ForegroundColor Red
    if ($PauseAtEnd) { [void](Read-Host 'Press Enter to close') }
    exit 1
}
if ($PauseAtEnd) { [void](Read-Host 'Press Enter to close') }
