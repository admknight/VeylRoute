[CmdletBinding()]
param(
    [switch]$PauseAtEnd,
    [ValidateSet('SystemWide','SelectedAppsOnly')]
    [string]$RoutingMode,
    [string]$Root,
    [string]$CancelFile = ''
)

$ErrorActionPreference = 'Stop'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
. (Join-Path $InternalRoot 'TorTunnel.Common.ps1')
. (Join-Path $InternalRoot 'TorTunnel.AppBypass.ps1')

function Pause-IfRequested {
    if ($PauseAtEnd) { [void](Read-Host 'Press Enter to close') }
}
# Cooperative cancellation: only the engine that owns session state performs rollback.
# The GUI never kills the Start process while it may be editing routes/firewall rules.
function Assert-TTNotCancelled {
    if ($CancelFile -and (Test-Path -LiteralPath $CancelFile -PathType Leaf)) {
        throw 'Connection cancelled by user request. Safe rollback is required.'
    }
}

function Select-TTRoutingModeForSession {
    param(
        [string]$RequestedMode,
        [int]$ExcludedCount,
        [int]$TorAppCount
    )

    if ($RequestedMode) {
        return ([string]$RequestedMode).ToLowerInvariant()
    }

    Write-Host ''
    Write-Host 'Choose routing mode for THIS SESSION:' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '[1] SystemWide'
    Write-Host '    All normal IPv4 TCP applications use Tor.'
    Write-Host ("    DIRECT exclusions configured: {0}" -f $ExcludedCount)
    Write-Host ''
    Write-Host '[2] SelectedAppsOnly'
    Write-Host '    Windows stays DIRECT; only configured TOR apps use Tor.'
    if ($TorAppCount -gt 0) {
        Write-Host ("    TOR applications configured: {0}" -f $TorAppCount)
    }
    else {
        Write-Host '    TOR applications configured: 0 (add one from START-HERE -> Manage TOR-only apps)' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '[Q] Cancel'
    Write-Host ''

    while ($true) {
        $answer = (Read-Host 'Select 1, 2, or Q').Trim()
        switch ($answer.ToLowerInvariant()) {
            '1' { return 'systemwide' }
            '2' { return 'selectedappsonly' }
            'q' { return $null }
            default { Write-Host 'Invalid selection. Enter 1, 2, or Q.' -ForegroundColor Yellow }
        }
    }
}

if (-not (Test-TTAdministrator)) {
    $elevationArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($PauseAtEnd) { $elevationArgs += ' -PauseAtEnd' }
    $elevationArgs += " -Root `"$Root`""
    if ($RoutingMode) { $elevationArgs += " -RoutingMode `"$RoutingMode`"" }
    if ($CancelFile) { $elevationArgs += " -CancelFile `"$CancelFile`"" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevationArgs
    exit
}

$runtimeInfo = $null
$stateFile = $null
$stopScript = Join-Path $InternalRoot 'Stop-TorTunnel.ps1'

try {
    Write-Host ''
    $TTVersion = Get-TTVersion -Root $Root
    Write-Host "=== TorTunnel Universal $TTVersion - Start ===" -ForegroundColor Cyan
    Write-Host "Portable root    : $Root"

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        throw 'Windows PowerShell 5.1 or newer is required.'
    }
    if ($env:OS -ne 'Windows_NT') {
        throw 'This package is for Windows only.'
    }
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This package requires 64-bit Windows.'
    }

    Test-TTRootWritable -Root $Root
    $settings = Get-TTSettings -Root $Root
    $layout = Resolve-TTLayout -Root $Root
    $runtimeInfo = Initialize-TTRuntimeForMachine -Root $Root -Settings $settings
    $stateFile = $runtimeInfo.StateFile

    $legacyStateFile = Join-Path $Root 'tunnel-state.json'
    if (Test-Path -LiteralPath $legacyStateFile) {
        throw 'A v2.1/legacy tunnel-state.json was found. Use START-HERE -> Advanced Recovery before starting a new session.'
    }

    if (Test-Path -LiteralPath $stateFile) {
        $existingState = $null
        try { $existingState = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json } catch {}
        if ($existingState -and [string]$existingState.MachineGuid -ne $runtimeInfo.MachineGuid) {
            Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
        }
        else {
            throw "A session/recovery state already exists. Use START-HERE -> Stop / Disconnect first: $stateFile"
        }
    }

    $manualRoutes = @(Test-TTManualTunnelRoutes)
    if ($manualRoutes.Count -gt 0) {
        throw 'Existing tun2socks /1 routes were detected. Stop or recover the older/manual tunnel before starting a new session.'
    }

    if (Get-Process -Name 'tun2socks' -ErrorAction SilentlyContinue) {
        throw 'tun2socks is already running. Stop the old tunnel first.'
    }

    # Routing mode is deliberately selected on every interactive Start. The value in
    # settings.json is not used as a persistent mode selector. An explicit
    # -RoutingMode parameter is available only for intentional automation.
    $excludedApps = @(Get-TTExcludedApps -Root $Root -Settings $settings)
    $torApps = @(Get-TTTorApps -Root $Root -Settings $settings)
    $sessionMode = Select-TTRoutingModeForSession -RequestedMode $RoutingMode -ExcludedCount $excludedApps.Count -TorAppCount $torApps.Count
    if (-not $sessionMode) {
        Write-Host ''
        Write-Host 'Start cancelled. No network changes were made.' -ForegroundColor Yellow
        Pause-IfRequested
        exit 0
    }
    $settings.RoutingMode = $sessionMode
    Write-Host ''
    Write-Host ("Session routing mode: {0}" -f $(if ($sessionMode -eq 'systemwide') { 'SystemWide' } else { 'SelectedAppsOnly' })) -ForegroundColor Green

    Assert-TTPortsFree -Settings $settings
    if ($settings.RoutingMode -eq 'systemwide') { Assert-TTDohSupport }

    $bridgeConfig = Get-TTBridgeConfig -Root $Root
    $generated = New-TTGeneratedTorrc -Root $Root -Layout $layout -Settings $settings -BridgeConfig $bridgeConfig

    Write-Host ''
    Write-Host '[0/10] Preflight checks...' -ForegroundColor Yellow
    $nativeArch = Get-TTNativeArchitecture
    Write-Host "Windows arch     : $nativeArch"
    if ($nativeArch -eq 'x86') { throw '32-bit Windows is not supported.' }
    if ($nativeArch -eq 'arm64') {
        throw 'ARM64 Windows was detected. This portable package uses the Windows x64/amd64 Tor, tun2socks and Wintun binaries from your current setup; use matching ARM64 binaries before running it on ARM64.'
    }

    $curlCommand = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curlCommand) {
        throw 'curl.exe was not found. Modern Windows 10/11 normally includes it.'
    }
    $managementCurl = [IO.Path]::GetFullPath([string]$curlCommand.Source)

    $torVerifyArgs = "--verify-config -f `"$($generated.Torrc)`""
    $verifyProc = Start-Process -FilePath $layout.TorExe -ArgumentList $torVerifyArgs -WorkingDirectory (Split-Path $layout.TorExe) -NoNewWindow -Wait -PassThru
    if ($verifyProc.ExitCode -ne 0) {
        throw "Tor rejected the generated configuration: $($generated.Torrc)"
    }

    $primary = Get-TTPrimaryIPv4
    $physicalAdapter = $primary.Adapter
    $physicalRoute = $primary.Route
    $physicalIndex = [int]$physicalAdapter.ifIndex
    $physicalAlias = [string]$physicalAdapter.Name
    $physicalGuid = ([guid]$physicalAdapter.InterfaceGuid).ToString('B')
    $gateway = [string]$physicalRoute.NextHop
    $relevantAdapters = @(Get-TTRelevantAdapters -PrimaryAdapter $physicalAdapter)
    $tunIP = Select-TTTunIPv4
    $physicalIPv4 = $null

    if ($settings.RoutingMode -eq 'systemwide') {
        if ($excludedApps.Count -gt 0) {
            $physicalIPv4 = Get-TTPrimarySourceIPv4 -InterfaceIndex $physicalIndex
            foreach ($app in $excludedApps) {
                $appFull = [IO.Path]::GetFullPath($app.Path)
                if ([string]::Equals($appFull,[IO.Path]::GetFullPath($layout.TorExe),[StringComparison]::OrdinalIgnoreCase) -or
                    [string]::Equals($appFull,[IO.Path]::GetFullPath($layout.TunExe),[StringComparison]::OrdinalIgnoreCase)) { throw "Tor/tun2socks cannot be placed in excluded-apps.txt: $($app.Path)" }
                if ([string]::Equals($appFull,$managementCurl,[StringComparison]::OrdinalIgnoreCase)) { throw "The Windows curl.exe used by TorTunnel health checks cannot be excluded: $($app.Path)." }
            }
            Test-TTAppBypassSupport -ExecutablePath $excludedApps[0].Path -InterfaceIndex $physicalIndex
            $edgeForConflict = Get-TTEdgeExecutable
            if ($settings.EdgeKillSwitch -and $edgeForConflict) {
                foreach ($app in $excludedApps) {
                    if ([string]::Equals([IO.Path]::GetFullPath($app.Path),[IO.Path]::GetFullPath($edgeForConflict),[StringComparison]::OrdinalIgnoreCase)) { throw 'Microsoft Edge is listed as a direct-bypass app while EdgeKillSwitch=true.' }
                }
            }
        }
    }
    else {
        if ($torApps.Count -lt 1) { throw 'SelectedAppsOnly mode requires at least one application in config\tor-apps.txt. Add one from START-HERE -> Manage TOR-only apps.' }
        foreach ($app in $torApps) {
            $appFull=[IO.Path]::GetFullPath($app.Path)
            if ([string]::Equals($appFull,[IO.Path]::GetFullPath($layout.TorExe),[StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals($appFull,[IO.Path]::GetFullPath($layout.TunExe),[StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals($appFull,$managementCurl,[StringComparison]::OrdinalIgnoreCase)) { throw "Tor, tun2socks, and TorTunnel's curl.exe cannot be TOR-only apps: $($app.Path)" }
        }
        Test-TTAppBypassSupport -ExecutablePath $torApps[0].Path -InterfaceIndex $physicalIndex
    }

    Write-Host "Internet adapter : $physicalAlias (ifIndex $physicalIndex)"
    Write-Host "Gateway          : $gateway"
    Write-Host "Wintun IPv4      : $tunIP/24"
    Write-Host "Bridge count     : $($bridgeConfig.Lines.Count)"
    Write-Host "Exit countries   : $(($settings.ExitCountries -join ',').ToUpperInvariant())"
    Write-Host "Routing mode     : $($settings.RoutingMode)"
    if ($settings.RoutingMode -eq 'systemwide') {
        Write-Host "Direct apps      : $($excludedApps.Count)"
        Write-Host "DNS mode         : strict DoH ($($settings.DohPrimary), $($settings.DohSecondary)); no plaintext fallback"
        if ($excludedApps.Count -gt 0) { Write-Host "Direct IPv4      : $physicalIPv4"; foreach($app in $excludedApps){Write-Host "  bypass          : $($app.Path)"} }
    }
    else {
        Write-Host "TOR-only apps    : $($torApps.Count)"
        Write-Host 'DNS mode         : system/direct (selected-app traffic is Tor-routed, Windows DNS is not)'
        foreach($app in $torApps){Write-Host "  TOR             : $($app.Path)"}
    }

    $dnsSnapshots = @()
    $ipv6Snapshots = @()
    foreach ($adapter in $relevantAdapters) {
        $dnsSnapshots += Get-TTDnsSnapshot -Adapter $adapter
        $v6 = Get-TTIPv6BindingSnapshot -Adapter $adapter
        if ($v6) { $ipv6Snapshots += $v6 }
    }
    $dohSnapshot = @()
    if ($settings.RoutingMode -eq 'systemwide') { $dohSnapshot = @(Get-TTDohSnapshot -Settings $settings) }

    $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    $quicExisted = $false
    $quicValue = $null
    if (Test-Path $edgePolicyPath) {
        $edgeProps = Get-ItemProperty -Path $edgePolicyPath -ErrorAction SilentlyContinue
        if ($edgeProps -and $null -ne $edgeProps.PSObject.Properties['QuicAllowed']) {
            $quicExisted = $true
            $quicValue = [int]$edgeProps.QuicAllowed
        }
    }


    $state = [ordered]@{
        Version               = (Get-TTVersionNumber -Root $Root)
        MachineGuid           = $runtimeInfo.MachineGuid
        RootPath              = $Root
        StartedAt             = (Get-Date).ToString('o')
        RoutingMode           = $settings.RoutingMode
        TunIP                 = $tunIP
        PhysicalGuid          = $physicalGuid
        PhysicalAlias         = $physicalAlias
        PhysicalIndex         = $physicalIndex
        Gateway               = $gateway
        PhysicalIPv4          = $physicalIPv4
        RelevantAdapterGuids  = @($relevantAdapters | ForEach-Object { ([guid]$_.InterfaceGuid).ToString('B') })
        DnsBefore             = $dnsSnapshots
        DohBefore             = $dohSnapshot
        DohConfiguredByScript = $false
        DnsChangedByScript    = $false
        DnsLeakBlockRules     = @()
        IPv6BindingsBefore    = $ipv6Snapshots
        IPv6ChangedByScript   = $false
        QuicPolicyExisted     = $quicExisted
        QuicPolicyValue       = $quicValue
        QuicPolicyChangedByScript = $false
        BridgeIPs             = @($bridgeConfig.IPs)
        BridgeRoutes          = @()
        EdgeKillSwitchRules   = @()
        RoutePoliciesBefore   = $null
        RoutePoliciesChanged  = $false
        AppBypassPolicies     = @()
        TorAppPolicies        = @()
        TorAppFirewallRules   = @()
        SystemWideRoutesInstalled = $false
        TorExe                = $layout.TorExe
        TunExe                = $layout.TunExe
        TorPid                = $null
        TunPid                = $null
        TunGuid               = $null
        TunIndex              = $null
        TunName               = $null
        GeneratedTorrc        = $generated.Torrc
        SocksPort             = [int]$settings.SocksPort
        ControlPortFile       = $generated.ControlPortFile
        ControlCookieFile     = $generated.ControlCookieFile
        PtSourcePath          = $generated.PtSourcePath
        PtExecPath            = $generated.PtExecPath
        PtShimRequired        = [bool]$generated.PtShimRequired
        TorStdoutLog          = (Join-Path $runtimeInfo.RuntimeDir 'tor.stdout.log')
        TorStderrLog          = (Join-Path $runtimeInfo.RuntimeDir 'tor.stderr.log')
    }
    Save-TTJson -Object $state -Path $stateFile


    Write-Host ''
    Assert-TTNotCancelled
    Write-Host '[1/10] Starting Tor through obfs4...' -ForegroundColor Yellow

    Install-TTTorPtExecShim -SourcePath $generated.PtSourcePath -ExecPath $generated.PtExecPath -Required ([bool]$generated.PtShimRequired)
    if ($generated.PtShimRequired) {
        Write-Host "Lyrebird shim     : $($generated.PtExecPath)"
    }

    $torStdout = [string]$state.TorStdoutLog
    $torStderr = [string]$state.TorStderrLog
    Remove-Item -LiteralPath $torStdout,$torStderr -Force -ErrorAction SilentlyContinue

    # Force a second notice logger to stdout so an early launch failure is always
    # captured, even if Tor exits before tor.log is created.
    $torArgs = "-f `"$($generated.Torrc)`" --Log `"notice stdout`""
    $torProc = Start-Process -FilePath $layout.TorExe -ArgumentList $torArgs -WorkingDirectory (Split-Path $layout.TorExe) -WindowStyle Hidden -RedirectStandardOutput $torStdout -RedirectStandardError $torStderr -PassThru
    $state.TorPid = $torProc.Id
    Save-TTJson -Object $state -Path $stateFile

    # Do not probe the SOCKS port with a long-running curl request as soon as
    # 9050 opens.  Tor opens the SOCKS listener at bootstrap 0%, while obfs4
    # may still be downloading consensus/microdescriptors.  Wait for Tor's
    # own 100% bootstrap signal first, then verify an actual SOCKS request.
    $deadline = (Get-Date).AddSeconds($settings.BootstrapTimeoutSeconds)
    $lastBootstrapPercent = -1
    $bootstrapDone = $false

    while ((Get-Date) -lt $deadline) {
        Assert-TTNotCancelled
        if (-not (Get-Process -Id $torProc.Id -ErrorAction SilentlyContinue)) {
            $tail = @()
            if (Test-Path -LiteralPath $torStdout) { $tail += @(Get-Content -LiteralPath $torStdout -Tail 16 -ErrorAction SilentlyContinue) }
            if (Test-Path -LiteralPath $torStderr) { $tail += @(Get-Content -LiteralPath $torStderr -Tail 16 -ErrorAction SilentlyContinue) }
            $detail = if ($tail.Count -gt 0) { "`r`nTor launch output:`r`n" + ($tail -join "`r`n") } else { '' }
            throw "Tor exited before bootstrap completed.$detail"
        }

        $bootstrap = Get-TTTorBootstrapStatus -LogPath $torStdout
        if ($bootstrap.Percent -ne $lastBootstrapPercent) {
            $lastBootstrapPercent = $bootstrap.Percent
            Write-Host ("Tor bootstrap     : {0}%" -f $bootstrap.Percent)
        }
        if ($bootstrap.Done) {
            $bootstrapDone = $true
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $bootstrapDone) {
        $tail = @()
        if (Test-Path -LiteralPath $torStdout) { $tail += @(Get-Content -LiteralPath $torStdout -Tail 20 -ErrorAction SilentlyContinue) }
        if (Test-Path -LiteralPath $torStderr) { $tail += @(Get-Content -LiteralPath $torStderr -Tail 20 -ErrorAction SilentlyContinue) }
        $detail = if ($tail.Count -gt 0) { "`r`nLast Tor output:`r`n" + ($tail -join "`r`n") } else { '' }
        throw "Tor did not reach 100% bootstrap within $($settings.BootstrapTimeoutSeconds) seconds.$detail"
    }

    # Bootstrap is complete.  Now verify that the SOCKS path can actually reach
    # the Internet.  Retry for up to 60 seconds so one slow/blocked check request
    # does not tear down an otherwise healthy Tor circuit.
    $torCheck = $null
    $verifyDeadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $verifyDeadline) {
        Assert-TTNotCancelled
        if (-not (Get-Process -Id $torProc.Id -ErrorAction SilentlyContinue)) {
            throw 'Tor exited after reaching bootstrap 100% but before SOCKS verification completed.'
        }
        $torCheck = Get-TTTorCheckViaSocks -SocksPort $settings.SocksPort
        if ($torCheck) { break }
        Start-Sleep -Seconds 3
    }
    if (-not $torCheck) {
        throw 'Tor reached bootstrap 100%, but the SOCKS Internet verification did not succeed within 60 seconds.'
    }
    Write-Host "Tor exit IP      : $($torCheck.IP)"

    Write-Host ''
    Assert-TTNotCancelled
    Write-Host '[2/10] Verifying Tor exit country...' -ForegroundColor Yellow
    $socksCountry = Get-TTGeoIpCountry -IPAddress ([string]$torCheck.IP) -GeoIPFile $layout.GeoIP
    if ($socksCountry) {
        Write-Host "Tor country      : $socksCountry"
        if ($socksCountry.ToLowerInvariant() -notin @($settings.ExitCountries)) {
            $message = "Tor's local GeoIP maps this exit to $socksCountry, outside allowed exits $(($settings.ExitCountries -join ',').ToUpperInvariant())."
            if ($settings.StrictExitCountry) { throw $message }
            Write-Warning $message
        }
    }
    else {
        if ($settings.StrictExitCountry) { throw 'Strict country verification enabled, but local Tor GeoIP could not identify the exit.' }
        Write-Host 'Tor country      : unavailable (local Tor GeoIP lookup failed)' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '[3/10] Creating direct bridge routes...' -ForegroundColor Yellow
    if ($settings.RoutingMode -eq 'systemwide') {
        $bridgeRouteStates = @()
        foreach ($ip in $bridgeConfig.IPs) {
            $existingDirect = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "$ip/32" -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceIndex -eq $physicalIndex -and $_.NextHop -eq $gateway } |
                Select-Object -First 1
            $created = $false
            if (-not $existingDirect) {
                New-NetRoute -AddressFamily IPv4 -DestinationPrefix "$ip/32" -InterfaceIndex $physicalIndex -NextHop $gateway -RouteMetric 1 -PolicyStore ActiveStore | Out-Null
                $created = $true
            }
            $bridgeRouteStates += [pscustomobject]@{ IP=$ip; CreatedByScript=$created }
        }
        $state.BridgeRoutes = $bridgeRouteStates
        Save-TTJson -Object $state -Path $stateFile

    }
    else {
        Write-Host 'Bridge bypass    : not required; system default route stays DIRECT'
    }

    Write-Host ''
    Write-Host '[4/10] Starting tun2socks/Wintun...' -ForegroundColor Yellow
    $tunBefore = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -eq 'tun2socks Tunnel' -and $_.Status -eq 'Up' } |
        ForEach-Object { ([guid]$_.InterfaceGuid).ToString('B') })

    $tunOut = Join-Path $runtimeInfo.RuntimeDir 'tun2socks.out.log'
    $tunErr = Join-Path $runtimeInfo.RuntimeDir 'tun2socks.err.log'
    Remove-Item -LiteralPath $tunOut,$tunErr -Force -ErrorAction SilentlyContinue

    $tunProc = Start-Process -FilePath $layout.TunExe -ArgumentList @('--device','wintun','--proxy',"socks5://127.0.0.1:$($settings.SocksPort)",'--loglevel','info') -WorkingDirectory $layout.TunDir -WindowStyle Hidden -RedirectStandardOutput $tunOut -RedirectStandardError $tunErr -PassThru
    $state.TunPid = $tunProc.Id
    Save-TTJson -Object $state -Path $stateFile

    $tunAdapter = $null
    $deadline = (Get-Date).AddSeconds(35)
    while ((Get-Date) -lt $deadline) {
        Assert-TTNotCancelled
        if (-not (Get-Process -Id $tunProc.Id -ErrorAction SilentlyContinue)) {
            throw "tun2socks exited before creating Wintun. Check: $tunErr"
        }
        $tunAdapter = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
            Where-Object {
                $_.InterfaceDescription -eq 'tun2socks Tunnel' -and
                $_.Status -eq 'Up' -and
                $tunBefore -notcontains ([guid]$_.InterfaceGuid).ToString('B')
            } |
            Sort-Object ifIndex -Descending |
            Select-Object -First 1
        if ($tunAdapter) { break }
        Start-Sleep -Milliseconds 700
    }
    if (-not $tunAdapter) { throw "No new active tun2socks Wintun adapter appeared. Check: $tunErr" }

    $tunName = [string]$tunAdapter.Name
    $tunIndex = [int]$tunAdapter.ifIndex
    $tunGuid = ([guid]$tunAdapter.InterfaceGuid).ToString('B')
    $state.TunName = $tunName
    $state.TunIndex = $tunIndex
    $state.TunGuid = $tunGuid
    Save-TTJson -Object $state -Path $stateFile

    & netsh.exe interface ipv4 set address "name=$tunName" source=static "addr=$tunIP" mask=255.255.255.0 gateway=none | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to assign $tunIP/24 to $tunName." }
    $assigned = Get-NetIPAddress -InterfaceIndex $tunIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -eq $tunIP -and $_.PrefixLength -eq 24 }
    if (-not $assigned) { throw "Wintun did not retain $tunIP/24." }
    Write-Host "Wintun adapter   : $tunName (ifIndex $tunIndex)"

    Write-Host ''
    Write-Host '[5/10] Applying mode-specific DNS/IPv6 protection...' -ForegroundColor Yellow
    if ($settings.RoutingMode -eq 'systemwide') {
        $state.DohConfiguredByScript = $true
        $state.DnsChangedByScript = $true
        Save-TTJson -Object $state -Path $stateFile
        Set-TTStrictDoh -Settings $settings
        $dohServers = @($settings.DohPrimary,$settings.DohSecondary)
        foreach ($adapter in $relevantAdapters) {
            try { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $dohServers -ErrorAction Stop } catch { throw "Could not configure strict DoH DNS servers on $($adapter.Name): $($_.Exception.Message)" }
        }
        Set-DnsClientServerAddress -InterfaceIndex $tunIndex -ServerAddresses $dohServers -ErrorAction Stop
        if ($settings.BlockPlainDns) {
            $dnsRuleNames=@()
            foreach($adapter in $relevantAdapters){foreach($proto in @('UDP','TCP')){
                $ruleName='TorTunnel-DNS-'+[guid]::NewGuid().ToString('N')
                New-NetFirewallRule -Name $ruleName -DisplayName 'TorTunnel Plain DNS Block' -Group 'TorTunnel Universal' -Direction Outbound -Action Block -Protocol $proto -RemotePort 53 -InterfaceAlias $adapter.Name -Profile Any | Out-Null
                $dnsRuleNames += $ruleName
            }}
            $state.DnsLeakBlockRules=$dnsRuleNames; Save-TTJson -Object $state -Path $stateFile
            Write-Host "Plain DNS block  : enabled on $($relevantAdapters.Count) physical adapter(s)"
        }
        if($settings.DisableIPv6){
            $state.IPv6ChangedByScript=$true; Save-TTJson -Object $state -Path $stateFile
            foreach($snapshot in $ipv6Snapshots){if([bool]$snapshot.Enabled){$adapter=Find-TTAdapterByGuid -GuidText ([string]$snapshot.InterfaceGuid); if($adapter){Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop|Out-Null}}}
            Disable-NetAdapterBinding -Name $tunName -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue|Out-Null
        }
        & ipconfig.exe /flushdns | Out-Null
    }
    else {
        # SelectedAppsOnly must not change the rest of Windows' DNS or physical
        # IPv6 configuration. Selected apps are fail-closed on physical adapters
        # in stage 7, and UDP is optionally blocked for those apps.
        Disable-NetAdapterBinding -Name $tunName -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Out-Null
        Write-Host 'System DNS/IPv6  : unchanged (normal Windows connection stays DIRECT)'
        Write-Host 'Selected-app DNS : Windows system resolver/direct; not Tor-private' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '[6/10] Applying mode-specific Edge settings...' -ForegroundColor Yellow
    $edgeExe = Get-TTEdgeExecutable
    $edgeRuleNames = @()
    $edgeIsTorApp = $false
    if ($edgeExe -and $settings.RoutingMode -eq 'selectedappsonly') {
        foreach($app in $torApps){if([string]::Equals([IO.Path]::GetFullPath($app.Path),[IO.Path]::GetFullPath($edgeExe),[StringComparison]::OrdinalIgnoreCase)){$edgeIsTorApp=$true;break}}
    }
    if ($settings.DisableEdgeQuic -and ($settings.RoutingMode -eq 'systemwide' -or $edgeIsTorApp)) {
        $state.QuicPolicyChangedByScript=$true; Save-TTJson -Object $state -Path $stateFile
        New-Item -Path $edgePolicyPath -Force | Out-Null
        New-ItemProperty -Path $edgePolicyPath -Name 'QuicAllowed' -PropertyType DWord -Value 0 -Force | Out-Null
        Write-Host 'Edge QUIC        : disabled for Tor-routed Edge traffic'
    }
    elseif ($settings.RoutingMode -eq 'selectedappsonly') { Write-Host 'Edge QUIC        : unchanged (Edge is not a selected TOR app)' }

    if ($settings.RoutingMode -eq 'systemwide' -and $settings.EdgeKillSwitch) {
        if ($edgeExe) {
            foreach($adapter in $relevantAdapters){
                $ruleName='TorTunnel-Edge-'+[guid]::NewGuid().ToString('N')
                New-NetFirewallRule -Name $ruleName -DisplayName 'TorTunnel Edge Kill-Switch' -Group 'TorTunnel Universal' -Direction Outbound -Action Block -Program $edgeExe -InterfaceAlias $adapter.Name -Profile Any|Out-Null
                $edgeRuleNames += $ruleName
            }
            Write-Host "Edge kill-switch : enabled on $($relevantAdapters.Count) Internet-capable adapter(s)"
        } else { Write-Warning 'Microsoft Edge was not found, so the Edge-specific kill-switch was not created.' }
    }
    $state.EdgeKillSwitchRules=$edgeRuleNames; Save-TTJson -Object $state -Path $stateFile

    Write-Host ''
    Write-Host '[7/10] Applying per-app routing policies...' -ForegroundColor Yellow
    $needsRoutePolicies = (($settings.RoutingMode -eq 'systemwide' -and $excludedApps.Count -gt 0) -or ($settings.RoutingMode -eq 'selectedappsonly' -and $torApps.Count -gt 0))
    if($needsRoutePolicies){
        $routePolicyBefore=Get-TTIPv4RoutePoliciesState
        $state.RoutePoliciesBefore=$routePolicyBefore; Save-TTJson -Object $state -Path $stateFile
        if($routePolicyBefore -ne 'enabled'){Set-TTIPv4RoutePoliciesState -State 'enabled';$state.RoutePoliciesChanged=$true;Save-TTJson -Object $state -Path $stateFile}
    }

    if($settings.RoutingMode -eq 'systemwide'){
        if($excludedApps.Count -gt 0){
            foreach($app in $excludedApps){
                $policyKey=Add-TTDirectAppPolicy -ExecutablePath $app.Path -InterfaceIndex $physicalIndex -SourceIPv4 $physicalIPv4 -GatewayIPv4 $gateway
                $entry=[pscustomobject]@{Path=[string]$app.Path;Name=[string]$app.Name;PolicyKey=[string]$policyKey}
                $state.AppBypassPolicies=@($state.AppBypassPolicies)+@($entry);Save-TTJson -Object $state -Path $stateFile
                Write-Host "DIRECT bypass    : $($app.Name)"
            }
            Write-Host "Bypass interface : $physicalAlias / $physicalIPv4 -> $gateway"
        } else { Write-Host 'DIRECT bypass    : none configured' }
    }
    else {
        Test-TTAppBypassSupport -ExecutablePath $torApps[0].Path -InterfaceIndex $tunIndex
        $torRuleNames=@()
        foreach($app in $torApps){
            $policyKey=Add-TTTorAppPolicy -ExecutablePath $app.Path -InterfaceIndex $tunIndex -TunIPv4 $tunIP
            $entry=[pscustomobject]@{Path=[string]$app.Path;Name=[string]$app.Name;PolicyKey=[string]$policyKey}
            $state.TorAppPolicies=@($state.TorAppPolicies)+@($entry);Save-TTJson -Object $state -Path $stateFile
            Write-Host "TOR route        : $($app.Name) -> $tunName"

            if($settings.TorAppKillSwitch){
                foreach($adapter in $relevantAdapters){
                    $rn='TorTunnel-TorApp-'+[guid]::NewGuid().ToString('N')
                    New-NetFirewallRule -Name $rn -DisplayName 'TorTunnel TOR-App Direct Block' -Group 'TorTunnel Universal' -Direction Outbound -Action Block -Program $app.Path -InterfaceAlias $adapter.Name -Profile Any|Out-Null
                    $torRuleNames += $rn
                }
            }
            if($settings.BlockTorAppUdp){
                $rn='TorTunnel-TorAppUDP-'+[guid]::NewGuid().ToString('N')
                New-NetFirewallRule -Name $rn -DisplayName 'TorTunnel TOR-App UDP Block' -Group 'TorTunnel Universal' -Direction Outbound -Action Block -Program $app.Path -Protocol UDP -Profile Any|Out-Null
                $torRuleNames += $rn
            }
        }
        $state.TorAppFirewallRules=$torRuleNames;Save-TTJson -Object $state -Path $stateFile
        Write-Host "TOR app policies : $($torApps.Count) active"
        if($settings.TorAppKillSwitch){Write-Host 'TOR kill-switch  : direct physical egress blocked for selected apps'}
        if($settings.BlockTorAppUdp){Write-Host 'TOR app UDP      : blocked (Tor transports TCP, not arbitrary UDP)'}
    }

    Write-Host ''
    Assert-TTNotCancelled
    Write-Host '[8/10] Applying routing mode...' -ForegroundColor Yellow
    if($settings.RoutingMode -eq 'systemwide'){
        & route.exe add 0.0.0.0 mask 128.0.0.0 $tunIP if $tunIndex metric $settings.RouteMetric | Out-Null
        if($LASTEXITCODE -ne 0){throw 'Failed to add 0.0.0.0/1 Wintun route.'}
        & route.exe add 128.0.0.0 mask 128.0.0.0 $tunIP if $tunIndex metric $settings.RouteMetric | Out-Null
        if($LASTEXITCODE -ne 0){throw 'Failed to add 128.0.0.0/1 Wintun route.'}
        $state.SystemWideRoutesInstalled=$true;Save-TTJson -Object $state -Path $stateFile
        Write-Host 'System IPv4      : Wintun/Tor via two /1 routes'
    } else {
        Write-Host 'System IPv4      : DIRECT; no /1 Wintun routes installed'
    }

    Write-Host ''
    Assert-TTNotCancelled
    Write-Host '[9/10] Verifying routing mode...' -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    $finalTor=$null
    if($settings.RoutingMode -eq 'systemwide'){
        $plainText=$null
        for($attempt=1;$attempt -le $settings.TransparentProbeAttempts;$attempt++){
            Assert-TTNotCancelled
            $plainText=Invoke-TTCurlText @('--silent','--show-error','--max-time','30','https://check.torproject.org/api/ip')
            if($plainText){break}
            if($attempt -lt $settings.TransparentProbeAttempts){
                Write-Warning "Tor transparent route probe $attempt/$($settings.TransparentProbeAttempts) unavailable; retrying without altering network safeguards."
                Start-Sleep -Seconds $settings.TransparentProbeDelaySeconds
            }
        }
        if(-not $plainText){throw 'Transparent curl test failed after Wintun routing was enabled.'}
        try{$plainTor=$plainText|ConvertFrom-Json}catch{throw 'Could not parse the transparent Tor check response.'}
        if(-not $plainTor.IsTor){throw 'Transparent IPv4 traffic is not exiting through Tor.'}
        $finalTor=$plainTor
        if(-not(Test-TTStrictDohConfiguration -Settings $settings)){throw 'Strict DoH configuration is no longer active.'}
        $systemDns=Resolve-DnsName -Name 'example.com' -Type A -ErrorAction Stop
        if(-not $systemDns){throw 'System DNS did not resolve using strict DNS-over-HTTPS.'}
        if($settings.DisableIPv6){$ipv6Probe=Invoke-TTCurlText @('-6','--silent','--max-time','5','https://api64.ipify.org');if($ipv6Probe){throw "IPv6 Internet access still succeeded ($ipv6Probe)."}}
    }
    else {
        $routeRows=@()
        foreach($prefix in @('0.0.0.0/1','128.0.0.0/1')){$routeRows += @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue|Where-Object{$_.InterfaceIndex -eq $tunIndex})}
        if($routeRows.Count -gt 0){throw 'SelectedAppsOnly mode unexpectedly has system-wide /1 routes on Wintun.'}
        foreach($entry in @($state.TorAppPolicies)){if(-not(Test-TTAppRoutePolicy -PolicyKey ([string]$entry.PolicyKey))){throw "TOR app policy is missing for $($entry.Path)"}}
        $finalTor=Get-TTTorCheckViaSocks -SocksPort $settings.SocksPort
        if(-not $finalTor){throw 'Tor SOCKS verification failed in SelectedAppsOnly mode.'}
        $directText=Invoke-TTCurlText @('--silent','--max-time','20','https://check.torproject.org/api/ip')
        if($directText){
            try{$directObj=$directText|ConvertFrom-Json;if($directObj.IsTor){throw 'The normal Windows curl path is still using Tor. SelectedAppsOnly requires the default system path to remain DIRECT.'}}catch{if($_.Exception.Message -like '*normal Windows curl path*'){throw}}
        }
        Write-Host 'System route      : DIRECT (verified: no TorTunnel /1 routes)'
        Write-Host 'TOR policy route  : active for selected executables'
        Write-Host 'DNS note          : Windows DNS remains on the normal/direct system resolver' -ForegroundColor Yellow
    }

    $country=Get-TTGeoIpCountry -IPAddress ([string]$finalTor.IP) -GeoIPFile $layout.GeoIP
    if ($settings.StrictExitCountry) {
        if (-not $country -or $country.ToLowerInvariant() -notin @($settings.ExitCountries)) {
            throw 'Final observed Tor exit could not be verified inside the selected country allow-list.'
        }
    }
    Write-Host ''
    Assert-TTNotCancelled
    Write-Host '[10/10] CONNECTED' -ForegroundColor Green
    Write-Host "Routing mode     : $($settings.RoutingMode) (saved for this session; Stop uses this state)"
    Write-Host "Tor exit IP      : $($finalTor.IP)"
    if($country){Write-Host "Reported country : $country (Tor local GeoIP)"}else{Write-Host 'Reported country : unavailable (local Tor GeoIP lookup failed)' -ForegroundColor Yellow}
    Write-Host "Internet via     : $physicalAlias"
    Write-Host "Portable root    : $Root"
    if($settings.RoutingMode -eq 'systemwide'){
        Write-Host "Direct apps      : $($excludedApps.Count)"
        Write-Host "DNS               : strict DoH via Tor route ($($settings.DohPrimary), $($settings.DohSecondary))"
        Write-Host ''
        Write-Host 'Normal IPv4 TCP applications now use Wintun -> tun2socks -> Tor.'
        if($excludedApps.Count -gt 0){Write-Host 'Apps in config\excluded-apps.txt use the physical connection directly.'}
    } else {
        Write-Host "TOR-only apps    : $($torApps.Count)"
        Write-Host 'DNS               : normal Windows/system DNS (DIRECT)'
        Write-Host ''
        Write-Host 'Windows and non-selected apps remain on the normal physical Internet connection.'
        Write-Host 'Only apps in config\tor-apps.txt receive IPv4 TCP routing policies to Wintun -> tun2socks -> Tor.'
        Write-Host 'Selected-app direct physical traffic is blocked when TorAppKillSwitch=true; selected-app UDP is blocked when BlockTorAppUdp=true.'
        Write-Host 'Important: Windows DNS for selected apps is not Tor-private in this mode.' -ForegroundColor Yellow
    }
    if($settings.DisableEdgeQuic -and ($settings.RoutingMode -eq 'systemwide' -or $edgeIsTorApp)){Write-Host 'Edge QUIC is disabled for the Tor-routed Edge session. Close/reopen Edge if it was already running.'}
    Write-Host 'Use START-HERE -> Stop / Disconnect BEFORE changing Wi-Fi, Ethernet, or hotspot connections.' -ForegroundColor Cyan

    if ($settings.OpenEdgeAfterConnect -and $edgeExe) {
        if ($settings.RoutingMode -eq 'systemwide' -or $edgeIsTorApp) { Start-Process -FilePath $edgeExe 'https://check.torproject.org/' }
        else { Write-Warning 'OpenEdgeAfterConnect was requested, but Edge is not in tor-apps.txt; Edge was not opened automatically.' }
    }

    Pause-IfRequested
}
catch {
    Write-Host ''
    Write-Host "START FAILED: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.InvocationInfo -and $_.InvocationInfo.ScriptName) {
        Write-Host ("Failure location: {0}:{1}" -f (Split-Path -Leaf $_.InvocationInfo.ScriptName), $_.InvocationInfo.ScriptLineNumber) -ForegroundColor DarkYellow
    }
    if ($stateFile -and (Test-Path -LiteralPath $stateFile) -and (Test-Path -LiteralPath $stopScript)) {
        Write-Host 'Rolling back changes...' -ForegroundColor Yellow
        try {
            $rollbackArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$stopScript`" -NoPause -Recovery -Root `"$Root`""
            $rollback = Start-Process powershell.exe -ArgumentList $rollbackArgs -WindowStyle Hidden -Wait -PassThru
            if ($rollback.ExitCode -ne 0) {
                Write-Warning "Rollback returned exit code $($rollback.ExitCode). Use START-HERE -> Stop / Disconnect and review its warnings."
            }
        }
        catch {
            Write-Warning "Automatic rollback could not be launched: $($_.Exception.Message)"
        }
    }
    Pause-IfRequested
    exit 1
}
