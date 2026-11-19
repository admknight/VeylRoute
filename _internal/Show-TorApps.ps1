[CmdletBinding()]
param([switch]$PauseAtEnd, [string]$Root)
$ErrorActionPreference='Stop'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
. (Join-Path $InternalRoot 'TorTunnel.Common.ps1')
. (Join-Path $InternalRoot 'TorTunnel.AppBypass.ps1')
try {
    $settings=Get-TTSettings -Root $Root
    $apps=@(Get-TTTorApps -Root $Root -Settings $settings)
    Write-Host ''; Write-Host '=== TorTunnel TOR-only app list ===' -ForegroundColor Cyan
    Write-Host "Mode usage      : choose SelectedAppsOnly during START-HERE -> Start / Connect"
    Write-Host "Configured apps : $($apps.Count)"
    foreach($app in $apps){Write-Host "  $($app.Path)"}
    if(Test-Path -LiteralPath (Join-Path $Root 'runtime\session-state.json')){Write-Host 'Session         : CONNECTED; list changes require Stop/Start.' -ForegroundColor Yellow}else{Write-Host 'Session         : DISCONNECTED'}
}
catch{Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red; exit 1}
if($PauseAtEnd){[void](Read-Host 'Press Enter to close')}
