[CmdletBinding()]
param([switch]$PauseAtEnd, [string]$Root)

$ErrorActionPreference = 'Stop'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
. (Join-Path $InternalRoot 'TorTunnel.Common.ps1')
. (Join-Path $InternalRoot 'TorTunnel.AppBypass.ps1')

function Finish([int]$Code) {
    if ($PauseAtEnd) { [void](Read-Host 'Press Enter to close') }
    exit $Code
}

if (-not (Test-TTAdministrator)) {
    $elevationArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($PauseAtEnd) { $elevationArgs += ' -PauseAtEnd' }
    $elevationArgs += " -Root `"$Root`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevationArgs
    exit
}

try {
    Write-Host ''
    $TTVersion = Get-TTVersion -Root $Root
    Write-Host "=== TorTunnel Universal $TTVersion - Preflight ===" -ForegroundColor Cyan
    Write-Host "Portable root      : $Root"

    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if (-not [Environment]::Is64BitOperatingSystem) { throw '64-bit Windows is required.' }
    Test-TTRootWritable -Root $Root

    $settings = Get-TTSettings -Root $Root
    $layout = Resolve-TTLayout -Root $Root
    $runtimeInfo = Initialize-TTRuntimeForMachine -Root $Root -Settings $settings

    $legacyStateFile = Join-Path $Root 'tunnel-state.json'
    if (Test-Path -LiteralPath $legacyStateFile) {
        throw 'A v2.1/legacy tunnel-state.json exists. Use START-HERE -> Advanced Recovery before starting.'
    }
    $manual = @(Test-TTManualTunnelRoutes)
    if ($manual.Count -gt 0) { throw 'Old/manual tun2socks /1 routes are still present. Use START-HERE -> Stop / Disconnect or Advanced Recovery.' }

    $bridges = Get-TTBridgeConfig -Root $Root
    $generated = New-TTGeneratedTorrc -Root $Root -Layout $layout -Settings $settings -BridgeConfig $bridges
    $primary = Get-TTPrimaryIPv4
    $tunIP = Select-TTTunIPv4

    $nativeArch = Get-TTNativeArchitecture
    Write-Host "Windows arch       : $nativeArch"
    if ($nativeArch -eq 'arm64') { throw 'ARM64 detected. The current portable binaries are x64/amd64; matching ARM64 binaries are required.' }
    if ($nativeArch -eq 'x86') { throw '32-bit Windows is not supported.' }
    Write-Host "Internet adapter   : $($primary.Adapter.Name) (ifIndex $($primary.Adapter.ifIndex))"
    Write-Host "Gateway            : $($primary.Route.NextHop)"
    Write-Host "Selected Wintun IP : $tunIP/24"
    Write-Host "Tor executable     : $($layout.TorExe)"
    Write-Host "Lyrebird           : $($layout.Lyrebird)"
    Write-Host "tun2socks          : $($layout.TunExe)"
    Write-Host "Wintun DLL         : $($layout.WintunDll)"
    Write-Host "Bridges            : $($bridges.Lines.Count)"
    Write-Host "Exit country       : $($settings.ExitCountry.ToUpperInvariant())"
    Write-Host 'Routing mode       : selected during each Start session'

    $curlCommand = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curlCommand) { throw 'curl.exe was not found.' }
    $managementCurl = [IO.Path]::GetFullPath([string]$curlCommand.Source)

    $excludedApps = @(Get-TTExcludedApps -Root $Root -Settings $settings)
    $torApps = @(Get-TTTorApps -Root $Root -Settings $settings)
    Write-Host "Configured DIRECT  : $($excludedApps.Count)"
    Write-Host "Configured TOR apps: $($torApps.Count)"

    # Validate common unsafe-list conflicts without selecting a session mode.
    foreach ($app in $excludedApps) {
        $full = [IO.Path]::GetFullPath($app.Path)
        if ([string]::Equals($full,[IO.Path]::GetFullPath($layout.TorExe),[StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($full,[IO.Path]::GetFullPath($layout.TunExe),[StringComparison]::OrdinalIgnoreCase)) { throw "Tor/tun2socks cannot be excluded: $($app.Path)" }
        if ([string]::Equals($full,$managementCurl,[StringComparison]::OrdinalIgnoreCase)) { throw "The Windows curl.exe used by TorTunnel health checks cannot be excluded: $($app.Path)" }
    }
    foreach ($app in $torApps) {
        $full = [IO.Path]::GetFullPath($app.Path)
        if ([string]::Equals($full,[IO.Path]::GetFullPath($layout.TorExe),[StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($full,[IO.Path]::GetFullPath($layout.TunExe),[StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($full,$managementCurl,[StringComparison]::OrdinalIgnoreCase)) { throw "Tor, tun2socks, and TorTunnel's curl.exe cannot be TOR-only apps: $($app.Path)" }
    }

    $systemWideReady = $true
    $systemWideReason = 'READY'
    try {
        Assert-TTDohSupport
        if ($excludedApps.Count -gt 0) {
            $edge = Get-TTEdgeExecutable
            if ($settings.EdgeKillSwitch -and $edge) {
                foreach ($app in $excludedApps) {
                    if ([string]::Equals([IO.Path]::GetFullPath($app.Path),[IO.Path]::GetFullPath($edge),[StringComparison]::OrdinalIgnoreCase)) { throw 'Microsoft Edge is excluded while EdgeKillSwitch=true.' }
                }
            }
            Test-TTAppBypassSupport -ExecutablePath $excludedApps[0].Path -InterfaceIndex ([int]$primary.Adapter.ifIndex)
        }
    }
    catch {
        $systemWideReady = $false
        $systemWideReason = $_.Exception.Message
    }

    $selectedReady = $true
    $selectedReason = 'READY'
    try {
        if ($torApps.Count -lt 1) { throw 'No TOR apps configured. Add one from START-HERE -> Manage TOR-only apps before selecting this mode.' }
        Test-TTAppBypassSupport -ExecutablePath $torApps[0].Path -InterfaceIndex ([int]$primary.Adapter.ifIndex)
    }
    catch {
        $selectedReady = $false
        $selectedReason = $_.Exception.Message
    }

    Write-Host ''
    Write-Host 'Mode readiness:' -ForegroundColor Cyan
    Write-Host (('  SystemWide       : ' + $systemWideReason)) -ForegroundColor $(if($systemWideReady){'Green'}else{'Yellow'})
    Write-Host (('  SelectedAppsOnly : ' + $selectedReason)) -ForegroundColor $(if($selectedReady){'Green'}else{'Yellow'})

    $torVersion = & $layout.TorExe --version 2>$null | Select-Object -First 1
    if ($torVersion) { Write-Host "Tor version        : $torVersion" }
    $tunVersion = & $layout.TunExe --version 2>$null
    if ($tunVersion) { Write-Host "tun2socks version  : $(($tunVersion -join ' | ').Trim())" }

    $torArgs = "--verify-config -f `"$($generated.Torrc)`""
    $verify = Start-Process -FilePath $layout.TorExe -ArgumentList $torArgs -WorkingDirectory (Split-Path $layout.TorExe) -NoNewWindow -Wait -PassThru
    if ($verify.ExitCode -ne 0) { throw 'Tor rejected the generated torrc.' }

    $stateFile = $runtimeInfo.StateFile
    if (Test-Path -LiteralPath $stateFile) {
        Write-Warning 'A session state exists. If connected, use Status/Stop. If a prior run crashed, use Stop to recover before Start.'
    }
    else {
        Assert-TTPortsFree -Settings $settings
        Write-Host 'Local DNS port 53   : not required; Windows ICS/Hotspot may keep using it'
    }

    $edge = Get-TTEdgeExecutable
    if ($edge) { Write-Host "Microsoft Edge     : $edge" }
    else { Write-Warning 'Microsoft Edge was not found.' }

    Write-Host ''
    if ($systemWideReady -or $selectedReady) {
        Write-Host 'RESULT             : READY FOR START' -ForegroundColor Green
        Write-Host 'START-HERE -> Start / Connect will ask which routing mode to use for that session.'
        Write-Host 'Start repeats the selected mode-specific checks before changing networking.'
        Finish 0
    }
    else {
        Write-Host 'RESULT             : NOT READY - neither routing mode passed its mode-specific readiness check.' -ForegroundColor Red
        Finish 1
    }
}
catch {
    Write-Host ''
    Write-Host "RESULT             : NOT READY - $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptName) {
        Write-Host ("Failure location   : {0}:{1}" -f (Split-Path -Leaf $_.InvocationInfo.ScriptName), $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkYellow
    }
    Finish 1
}
