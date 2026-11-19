[CmdletBinding()]
param(
    [switch]$NoPause,
    [switch]$PauseAtEnd,
    [switch]$Recovery,
    [string]$Root
)

$ErrorActionPreference = 'Continue'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
. (Join-Path $InternalRoot 'TorTunnel.Common.ps1')
. (Join-Path $InternalRoot 'TorTunnel.AppBypass.ps1')

function Pause-IfRequested {
    if ($PauseAtEnd -and -not $NoPause) { [void](Read-Host 'Press Enter to close') }
}

if (-not (Test-TTAdministrator)) {
    $elevationArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($NoPause) { $elevationArgs += ' -NoPause' }
    if ($PauseAtEnd) { $elevationArgs += ' -PauseAtEnd' }
    if ($Recovery) { $elevationArgs += ' -Recovery' }
    $elevationArgs += " -Root `"$Root`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevationArgs
    exit
}

Write-Host ''
$TTVersion = Get-TTVersion -Root $Root
Write-Host "=== TorTunnel Universal $TTVersion - Stop ===" -ForegroundColor Cyan

$runtime = Join-Path $Root 'runtime'
$stateFile = Join-Path $runtime 'session-state.json'
if (-not (Test-Path -LiteralPath $stateFile)) {
    Write-Host 'No v3 session state exists. TorTunnel is already stopped, or this folder has not started a session.' -ForegroundColor Yellow
    Pause-IfRequested
    exit 0
}

try { $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json -ErrorAction Stop }
catch {
    Write-Host "Cannot read session state: $($_.Exception.Message)" -ForegroundColor Red
    Pause-IfRequested
    exit 1
}

$currentMachine = Get-TTMachineGuid
if ([string]$state.MachineGuid -ne $currentMachine) {
    $stale = Join-Path $runtime ('stale-session-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    Move-Item -LiteralPath $stateFile -Destination $stale -Force -ErrorAction SilentlyContinue
    Write-Warning 'The saved session belongs to another computer. It was archived and no network settings on this PC were changed.'
    Write-Host "Archived state: $stale"
    Pause-IfRequested
    exit 0
}

$errors = New-Object 'System.Collections.Generic.List[string]'
$tunIP = [string]$state.TunIP
$tunIndex = if ($state.TunIndex) { [int]$state.TunIndex } else { -1 }
$sessionMode = if ($state.PSObject.Properties['RoutingMode']) { [string]$state.RoutingMode } else { 'systemwide' }
Write-Host "Session routing mode : $sessionMode" -ForegroundColor Cyan

Write-Host '[1/9] Removing mode-specific Wintun Internet routes...' -ForegroundColor Yellow
try {
    foreach ($prefix in @('0.0.0.0/1','128.0.0.0/1')) {
        # Windows can expose these as on-link routes (NextHop 0.0.0.0), so
        # remove them by the saved Wintun interface index whenever available.
        Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue |
            Where-Object {
                if ($tunIndex -ge 0) { $_.InterfaceIndex -eq $tunIndex }
                else { $_.NextHop -eq $tunIP }
            } |
            Remove-NetRoute -Confirm:$false -ErrorAction Stop
    }
}
catch { $errors.Add("Failed to remove Wintun route(s): $($_.Exception.Message)") }

Write-Host '[2/9] Removing per-app routing policies...' -ForegroundColor Yellow
foreach ($entry in @($state.AppBypassPolicies)) {
    if (-not $entry -or -not $entry.PolicyKey) { continue }
    try {
        $rc = Remove-TTDirectAppPolicy -PolicyKey ([string]$entry.PolicyKey)
        # If Windows already discarded the non-persistent policy (for example after
        # a reboot), treat "provider context not found" / generic not-found as clean.
        if ($rc -ne 0 -and $rc -ne [uint32]0x80320006 -and $rc -ne [uint32]0x80320008) {
            throw ("WFP delete returned 0x{0:X8}" -f $rc)
        }
    }
    catch { $errors.Add("Failed to remove direct-bypass policy for $($entry.Path): $($_.Exception.Message)") }
}


$torPoliciesToRemove = @()
if ($state.PSObject.Properties['TorAppPolicies']) { $torPoliciesToRemove = @($state.TorAppPolicies) }
foreach ($entry in $torPoliciesToRemove) {
    if (-not $entry -or -not $entry.PolicyKey) { continue }
    try {
        $rc=Remove-TTAppRoutePolicy -PolicyKey ([string]$entry.PolicyKey)
        if($rc -ne 0 -and $rc -ne [uint32]0x80320006 -and $rc -ne [uint32]0x80320008){throw ("WFP delete returned 0x{0:X8}" -f $rc)}
    } catch { $errors.Add("Failed to remove TOR-app policy for $($entry.Path): $($_.Exception.Message)") }
}

if ($state.PSObject.Properties['RoutePoliciesBefore']) {
    $before = [string]$state.RoutePoliciesBefore
    if ($before -eq 'disabled' -and [bool]$state.RoutePoliciesChanged) {
        try { Set-TTIPv4RoutePoliciesState -State 'disabled' }
        catch { $errors.Add("Failed to restore Windows IPv4 routepolicies=disabled: $($_.Exception.Message)") }
    }
    elseif ($before -eq 'unknown' -and [bool]$state.RoutePoliciesChanged) {
        Write-Warning 'The original Windows routepolicies state was unknown, so routepolicies is being left enabled.'
    }
}

Write-Host '[3/9] Removing Edge/DNS leak-block firewall rules...' -ForegroundColor Yellow
$firewallRules = @()
if ($state.PSObject.Properties['EdgeKillSwitchRules']) { $firewallRules += @($state.EdgeKillSwitchRules) }
if ($state.PSObject.Properties['DnsLeakBlockRules']) { $firewallRules += @($state.DnsLeakBlockRules) }
if ($state.PSObject.Properties['TorAppFirewallRules']) { $firewallRules += @($state.TorAppFirewallRules) }
foreach ($ruleName in $firewallRules) {
    if (-not $ruleName) { continue }
    try { Get-NetFirewallRule -Name ([string]$ruleName) -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop }
    catch { $errors.Add("Failed to remove firewall rule $ruleName : $($_.Exception.Message)") }
}

Write-Host '[4/9] Restoring DNS, DoH resolver settings and IPv6...' -ForegroundColor Yellow
$restoreDns = if ($state.PSObject.Properties['DnsChangedByScript']) { [bool]$state.DnsChangedByScript } else { $true }
if ($restoreDns) {
    foreach ($dns in @($state.DnsBefore)) {
        if (-not $dns) { continue }
        try {
            $adapter = Find-TTAdapterByGuid -GuidText ([string]$dns.InterfaceGuid)
            if (-not $adapter) { throw "Adapter $($dns.InterfaceAlias) is not currently available." }
            if ([bool]$dns.WasDhcp) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
            }
            else {
                $servers = @($dns.Servers) | Where-Object { $_ }
                if ($servers.Count -lt 1) { throw 'Saved static DNS list is empty.' }
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
            }
        }
        catch { $errors.Add("Failed to restore DNS for $($dns.InterfaceAlias): $($_.Exception.Message)") }
    }}


if ($state.PSObject.Properties['DohConfiguredByScript'] -and [bool]$state.DohConfiguredByScript -and $state.PSObject.Properties['DohBefore']) {
    try { Restore-TTDohSnapshot -Snapshot @($state.DohBefore) }
    catch { $errors.Add("Failed to restore previous DNS-over-HTTPS resolver settings: $($_.Exception.Message)") }
}

$restoreIPv6 = if ($state.PSObject.Properties['IPv6ChangedByScript']) { [bool]$state.IPv6ChangedByScript } else { $true }
if ($restoreIPv6) {
    foreach ($snapshot in @($state.IPv6BindingsBefore)) {
        if (-not $snapshot) { continue }
        try {
            $adapter = Find-TTAdapterByGuid -GuidText ([string]$snapshot.InterfaceGuid)
            if (-not $adapter) { throw "Adapter $($snapshot.InterfaceAlias) is not currently available." }
            if ([bool]$snapshot.Enabled) {
                Enable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop | Out-Null
            }
            else {
                Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop | Out-Null
            }
        }
        catch { $errors.Add("Failed to restore IPv6 for $($snapshot.InterfaceAlias): $($_.Exception.Message)") }
    }}


Write-Host '[5/9] Restoring Edge QUIC policy...' -ForegroundColor Yellow
$restoreQuic = if ($state.PSObject.Properties['QuicPolicyChangedByScript']) { [bool]$state.QuicPolicyChangedByScript } else { $true }
if ($restoreQuic) {
    try {
        $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        if ([bool]$state.QuicPolicyExisted) {
            New-Item -Path $edgePolicyPath -Force | Out-Null
            New-ItemProperty -Path $edgePolicyPath -Name 'QuicAllowed' -PropertyType DWord -Value ([int]$state.QuicPolicyValue) -Force | Out-Null
        }
        else {
            Remove-ItemProperty -Path $edgePolicyPath -Name 'QuicAllowed' -ErrorAction SilentlyContinue
        }
    }
    catch { $errors.Add("Failed to restore Edge QUIC policy: $($_.Exception.Message)") }}


Write-Host '[6/9] Stopping tun2socks...' -ForegroundColor Yellow
if ($state.TunPid) {
    Stop-TTOwnedProcess -ProcessId ([int]$state.TunPid) -ExpectedPath ([string]$state.TunExe) -Errors $errors
}
Start-Sleep -Milliseconds 800

Write-Host '[7/9] Removing bridge bypass routes...' -ForegroundColor Yellow
foreach ($entry in @($state.BridgeRoutes)) {
    if (-not $entry -or -not [bool]$entry.CreatedByScript) { continue }
    try {
        $adapter = Find-TTAdapterByGuid -GuidText ([string]$state.PhysicalGuid)
        if (-not $adapter) { throw "Original Internet adapter $($state.PhysicalAlias) is unavailable." }
        Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "$($entry.IP)/32" -ErrorAction SilentlyContinue |
            Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex -and $_.NextHop -eq [string]$state.Gateway } |
            Remove-NetRoute -Confirm:$false -ErrorAction Stop
    }
    catch { $errors.Add("Failed to remove bridge route for $($entry.IP): $($_.Exception.Message)") }
}

Write-Host '[8/9] Stopping Tor and flushing DNS...' -ForegroundColor Yellow
if ($state.TorPid) {
    Stop-TTOwnedProcess -ProcessId ([int]$state.TorPid) -ExpectedPath ([string]$state.TorExe) -Errors $errors
}
if ($state.PSObject.Properties['PtShimRequired'] -and [bool]$state.PtShimRequired -and $state.PSObject.Properties['PtExecPath']) {
    try {
        $ptShim = [string]$state.PtExecPath
        if ($ptShim -and (Test-Path -LiteralPath $ptShim -PathType Leaf)) {
            Remove-Item -LiteralPath $ptShim -Force -ErrorAction Stop
            $ptDir = Split-Path -Parent $ptShim
            if ($ptDir -and (Test-Path -LiteralPath $ptDir) -and -not (Get-ChildItem -LiteralPath $ptDir -Force -ErrorAction SilentlyContinue)) {
                Remove-Item -LiteralPath $ptDir -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch { $errors.Add("Failed to remove temporary lyrebird shim: $($_.Exception.Message)") }
}
try { & ipconfig.exe /flushdns | Out-Null } catch {}

Write-Host '[9/9] Final compatibility recovery...' -ForegroundColor Yellow
if ($state.PSObject.Properties['IcsStoppedByScript'] -and [bool]$state.IcsStoppedByScript -and
    $state.PSObject.Properties['IcsWasRunning'] -and [bool]$state.IcsWasRunning) {
    try {
        $dnsPort = 53

        $deadline = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $deadline) {
            if (-not (Get-NetUDPEndpoint -LocalPort $dnsPort -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 400
        }

        Start-Service -Name 'SharedAccess' -ErrorAction Stop
        $ics = Get-Service -Name 'SharedAccess' -ErrorAction Stop
        $ics.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(20))
        Write-Host 'Legacy ICS state    : RESTORED' -ForegroundColor Green
    }
    catch {
        $errors.Add("Failed to restart Internet Connection Sharing (SharedAccess): $($_.Exception.Message)")
    }
}

if ($errors.Count -eq 0) {
    Remove-Item -LiteralPath $stateFile -Force -ErrorAction SilentlyContinue
    Write-Host ''
    if ($Recovery) { Write-Host 'Rollback/recovery completed successfully.' -ForegroundColor Green }
    else { Write-Host "TorTunnel disconnected. Settings created by the '$sessionMode' session were removed/restored." -ForegroundColor Green }
    Write-Host 'If Edge is open, restart Edge so the restored QUIC policy is picked up.'
    Pause-IfRequested
    exit 0
}
else {
    Write-Host ''
    Write-Host 'TorTunnel stopped with restoration warnings. The state file was kept so recovery information is not lost:' -ForegroundColor Red
    Write-Host "  $stateFile"
    foreach ($item in $errors) { Write-Host " - $item" -ForegroundColor Red }
    Write-Host 'Resolve the warnings and run Stop again before starting another session.' -ForegroundColor Yellow
    Pause-IfRequested
    exit 1
}
