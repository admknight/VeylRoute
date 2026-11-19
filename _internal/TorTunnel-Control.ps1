[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
. (Join-Path $InternalRoot 'TorTunnel.Common.ps1')

if (-not (Test-TTAdministrator)) {
    $argsLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Root `"$Root`""
    $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argsLine -Wait -PassThru
    exit $p.ExitCode
}

$TTVersion = Get-TTVersion -Root $Root
$stateFile = Join-Path $Root 'runtime\session-state.json'
$TTCredits = Get-TTProductCredits

function Show-TTBanner {
    Write-Host '  _______          _______                      _ ' -ForegroundColor Cyan
    Write-Host ' |__   __|        |__   __|                    | |' -ForegroundColor Cyan
    Write-Host '    | | ___  _ __    | |_   _ _ __  _ __   ___| |' -ForegroundColor Cyan
    Write-Host '    | |/ _ \| ''__|   | | | | | ''_ \| ''_ \ / _ \ |' -ForegroundColor Cyan
    Write-Host '    | | (_) | |      | | |_| | | | | | | |  __/ |' -ForegroundColor Cyan
    Write-Host '    |_|\___/|_|      |_|\__,_|_| |_|_| |_|\___|_|' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "TorTunnel Universal $TTVersion" -ForegroundColor White
    Write-Host "Author / Programmed by : $($TTCredits.Author)" -ForegroundColor DarkCyan
    Write-Host "Company                : $($TTCredits.Company)" -ForegroundColor DarkCyan
    Write-Host "Contact                : $($TTCredits.Email) / $($TTCredits.Phone)" -ForegroundColor DarkCyan
}

function Show-TTAbout {
    Clear-Host
    Show-TTBanner
    Write-Host ''
    Write-Host 'ABOUT / CREDITS' -ForegroundColor Cyan
    Write-Host '---------------' -ForegroundColor Cyan
    Write-Host 'TorTunnel Universal is a portable Windows automation layer for Tor, obfs4, Wintun, tun2socks, routing controls, leak protection, health checks, and per-application routing modes.'
    Write-Host ''
    Write-Host "Author / Programmed by : $($TTCredits.Author)"
    Write-Host "Company                : $($TTCredits.Company)"
    Write-Host "Email                  : $($TTCredits.Email)"
    Write-Host "Phone                  : $($TTCredits.Phone)"
    Write-Host "Version                : $TTVersion"
    Write-Host ''
    [void](Read-Host 'Press Enter to return')
}

function Invoke-TTChild {
    param(
        [Parameter(Mandatory=$true)][string]$ScriptName,
        [string[]]$ExtraArgs = @()
    )
    $script = Join-Path $InternalRoot $ScriptName
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        Write-Host "Missing internal script: $script" -ForegroundColor Red
        [void](Read-Host 'Press Enter to continue')
        return
    }
    $launch = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-Root',$Root)
    if ($ExtraArgs) { $launch += $ExtraArgs }
    & powershell.exe @launch
}

function Get-TTSessionLabel {
    if (-not (Test-Path -LiteralPath $stateFile)) { return 'DISCONNECTED' }
    try {
        $s = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -ErrorAction Stop
        $m = if ($s.PSObject.Properties['RoutingMode']) { [string]$s.RoutingMode } else { 'unknown' }
        return ('CONNECTED / ' + $m)
    }
    catch { return 'RECOVERY STATE PRESENT' }
}

function Invoke-TTLegacyLayoutCleanup {
    # v3.5 introduced a single-entry control center.  When upgrading from earlier
    # releases, move known old root launchers/scripts out of the way after the
    # tunnel is disconnected.  They are backed up, not deleted.
    if (Test-Path -LiteralPath $stateFile) { return }
    $legacyNames = @(
        'Add-ExcludedApp.cmd','Add-ExcludedApp.ps1','Add-TorApp.cmd','Add-TorApp.ps1',
        'Check-TorTunnel.cmd','Check-TorTunnel.ps1','Emergency-Reset-TorTunnel.cmd','Emergency-Reset-TorTunnel.ps1',
        'Remove-ExcludedApp.cmd','Remove-ExcludedApp.ps1','Remove-TorApp.cmd','Remove-TorApp.ps1',
        'Set-RoutingMode.cmd','Set-RoutingMode.ps1','Show-ExcludedApps.cmd','Show-ExcludedApps.ps1',
        'Show-TorApps.cmd','Show-TorApps.ps1','Start-TorTunnel.cmd','Start-TorTunnel.ps1',
        'Status-TorTunnel.cmd','Status-TorTunnel.ps1','Stop-TorTunnel.cmd','Stop-TorTunnel.ps1',
        'TorTunnel.AppBypass.ps1','TorTunnel.Common.ps1','COPY-INTO-YOUR-TORTUNNEL.txt','UPDATE-NOTES.txt'
    )
    $present = @($legacyNames | Where-Object { Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf })
    if ($present.Count -eq 0) { return }
    $runtime = Join-Path $Root 'runtime'
    if (-not (Test-Path -LiteralPath $runtime)) { New-Item -ItemType Directory -Path $runtime -Force | Out-Null }
    $backup = Join-Path $runtime ('legacy-layout-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($name in $present) {
        Move-Item -LiteralPath (Join-Path $Root $name) -Destination (Join-Path $backup $name) -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Organized older root files: $($present.Count) item(s) moved to:" -ForegroundColor DarkYellow
    Write-Host "  $backup" -ForegroundColor DarkYellow
    Start-Sleep -Seconds 2
}

function Show-TTAppMenu {
    param([ValidateSet('Tor','Direct')][string]$Kind)
    while ($true) {
        Clear-Host
        Show-TTBanner
        Write-Host ''
        Write-Host 'APP MANAGER' -ForegroundColor Cyan
        if ($Kind -eq 'Tor') {
            Write-Host 'TOR-only apps are used only in SelectedAppsOnly mode.'
            Write-Host ''
            Write-Host '[1] Show TOR-only apps'
            Write-Host '[2] Add TOR-only app'
            Write-Host '[3] Remove TOR-only app'
        } else {
            Write-Host 'DIRECT-bypass apps are used only in SystemWide mode.'
            Write-Host ''
            Write-Host '[1] Show DIRECT-bypass apps'
            Write-Host '[2] Add DIRECT-bypass app'
            Write-Host '[3] Remove DIRECT-bypass app'
        }
        Write-Host '[B] Back'
        Write-Host ''
        $choice = (Read-Host 'Select').Trim().ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($Kind -eq 'Tor') {
            switch ($choice) {
                '1' { Invoke-TTChild 'Show-TorApps.ps1' @('-PauseAtEnd') }
                '2' { Invoke-TTChild 'Add-TorApp.ps1' @('-PauseAtEnd') }
                '3' { Invoke-TTChild 'Remove-TorApp.ps1' @('-PauseAtEnd') }
                default { Write-Host 'Invalid selection.' -ForegroundColor Yellow; Start-Sleep 1 }
            }
        } else {
            switch ($choice) {
                '1' { Invoke-TTChild 'Show-ExcludedApps.ps1' @('-PauseAtEnd') }
                '2' { Invoke-TTChild 'Add-ExcludedApp.ps1' @('-PauseAtEnd') }
                '3' { Invoke-TTChild 'Remove-ExcludedApp.ps1' @('-PauseAtEnd') }
                default { Write-Host 'Invalid selection.' -ForegroundColor Yellow; Start-Sleep 1 }
            }
        }
    }
}

Invoke-TTLegacyLayoutCleanup

while ($true) {
    Clear-Host
    $session = Get-TTSessionLabel
    Show-TTBanner
    Write-Host ''
    Write-Host 'CONTROL CENTER' -ForegroundColor Cyan
    Write-Host "Portable root : $Root"
    Write-Host "Session       : $session" -ForegroundColor $(if ($session -like 'CONNECTED*') {'Green'} elseif ($session -eq 'DISCONNECTED') {'Yellow'} else {'Red'})
    Write-Host ''
    Write-Host '[1] Start / Connect'
    Write-Host '    Choose SystemWide or SelectedAppsOnly for this session.'
    Write-Host '[2] Status / Health Check'
    Write-Host '[3] Stop / Disconnect'
    Write-Host '[4] Manage TOR-only apps        (SelectedAppsOnly mode)'
    Write-Host '[5] Manage DIRECT-bypass apps   (SystemWide mode)'
    Write-Host '[6] Check Setup / Preflight'
    Write-Host '[7] Open User Guide'
    Write-Host '[8] About / Credits'
    Write-Host '[A] Advanced Recovery'
    Write-Host '[Q] Quit'
    Write-Host ''
    $choice = (Read-Host 'Select').Trim().ToLowerInvariant()
    switch ($choice) {
        '1' { Invoke-TTChild 'Start-TorTunnel.ps1' @('-PauseAtEnd') }
        '2' { Invoke-TTChild 'Status-TorTunnel.ps1' @('-PauseAtEnd') }
        '3' { Invoke-TTChild 'Stop-TorTunnel.ps1' @('-PauseAtEnd') }
        '4' { Show-TTAppMenu -Kind Tor }
        '5' { Show-TTAppMenu -Kind Direct }
        '6' { Invoke-TTChild 'Check-TorTunnel.ps1' @('-PauseAtEnd') }
        '7' {
            $guide = Join-Path $Root 'docs\USER-GUIDE.txt'
            if (Test-Path -LiteralPath $guide) { Start-Process notepad.exe -ArgumentList ('"' + $guide + '"') }
            else { Write-Host "User guide not found: $guide" -ForegroundColor Red; Start-Sleep 2 }
        }
        '8' { Show-TTAbout }
        'a' {
            Write-Host ''
            Write-Host 'Advanced Recovery is for stale/crashed/legacy tunnel state.' -ForegroundColor Yellow
            Write-Host 'Use normal Stop first whenever possible.' -ForegroundColor Yellow
            $confirm = (Read-Host 'Type RECOVER to continue, or press Enter to cancel').Trim()
            if ($confirm -ceq 'RECOVER') { Invoke-TTChild 'Emergency-Reset-TorTunnel.ps1' @('-PauseAtEnd') }
        }
        'q' { exit 0 }
        default { Write-Host 'Invalid selection.' -ForegroundColor Yellow; Start-Sleep 1 }
    }
    Invoke-TTLegacyLayoutCleanup
}
