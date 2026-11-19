[CmdletBinding()]
param([switch]$PauseAtEnd, [string]$Root)

$ErrorActionPreference = 'Continue'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
. (Join-Path $InternalRoot 'TorTunnel.Common.ps1')

function Pause-IfRequested {
    if ($PauseAtEnd) { [void](Read-Host 'Press Enter to close') }
}

if (-not (Test-TTAdministrator)) {
    $elevationArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($PauseAtEnd) { $elevationArgs += ' -PauseAtEnd' }
    $elevationArgs += " -Root `"$Root`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevationArgs
    exit
}

Write-Host ''
$TTVersion = Get-TTVersion -Root $Root
Write-Host "=== TorTunnel Universal $TTVersion - Emergency/Legacy Reset ===" -ForegroundColor Cyan

$runtimeState = Join-Path $Root 'runtime\session-state.json'
if (Test-Path -LiteralPath $runtimeState) {
    Write-Host 'A v3.x session state exists. Running the normal Stop script...' -ForegroundColor Yellow
    $stopArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InternalRoot 'Stop-TorTunnel.ps1')`" -NoPause"
    $p = Start-Process powershell.exe -ArgumentList $stopArgs -Wait -PassThru
    Pause-IfRequested
    exit $p.ExitCode
}

$legacyStateFile = Join-Path $Root 'tunnel-state.json'
if (Test-Path -LiteralPath $legacyStateFile) {
    Write-Host 'A v2.1/legacy state file was found. Restoring from its saved settings...' -ForegroundColor Yellow
    $errors = New-Object 'System.Collections.Generic.List[string]'
    try { $legacy = Get-Content -LiteralPath $legacyStateFile -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch {
        Write-Host "Could not read legacy state: $($_.Exception.Message)" -ForegroundColor Red
        Pause-IfRequested
        exit 1
    }

    $layout = $null
    try { $layout = Resolve-TTLayout -Root $Root } catch { $errors.Add("Could not resolve portable executables: $($_.Exception.Message)") }

    Write-Host '[1/7] Removing legacy Wintun routes...'
    $legacyTunIndex = if ($legacy.TunIndex) { [int]$legacy.TunIndex } else { -1 }
    foreach ($prefix in @('0.0.0.0/1','128.0.0.0/1')) {
        try {
            Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue |
                Where-Object { $legacyTunIndex -lt 0 -or $_.InterfaceIndex -eq $legacyTunIndex } |
                Remove-NetRoute -Confirm:$false -ErrorAction Stop
        }
        catch { $errors.Add("Failed to remove legacy route $prefix : $($_.Exception.Message)") }
    }

    Write-Host '[2/7] Removing legacy Edge firewall rule...'
    if ($legacy.EdgeKillSwitchRule) {
        try { Get-NetFirewallRule -Name ([string]$legacy.EdgeKillSwitchRule) -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction Stop }
        catch { $errors.Add("Failed to remove legacy Edge firewall rule: $($_.Exception.Message)") }
    }
    Get-NetFirewallRule -Group 'TorTunnel' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue

    Write-Host '[3/7] Restoring legacy DNS and IPv6 snapshots...'
    foreach ($dns in @($legacy.DnsBefore)) {
        if (-not $dns) { continue }
        try {
            $adapter = Find-TTAdapterByGuid -GuidText ([string]$dns.InterfaceGuid)
            if (-not $adapter) { throw "Adapter $($dns.InterfaceAlias) is not available." }
            if ([bool]$dns.WasDhcp) {
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses -ErrorAction Stop
            }
            else {
                $servers = @($dns.Servers) | Where-Object { $_ }
                if ($servers.Count -lt 1) { throw 'Saved static DNS list is empty.' }
                Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $servers -ErrorAction Stop
            }
        }
        catch { $errors.Add("Failed to restore legacy DNS: $($_.Exception.Message)") }
    }
    foreach ($snapshot in @($legacy.IPv6BindingsBefore)) {
        if (-not $snapshot) { continue }
        try {
            $adapter = Find-TTAdapterByGuid -GuidText ([string]$snapshot.InterfaceGuid)
            if (-not $adapter) { throw "Adapter $($snapshot.InterfaceAlias) is not available." }
            if ([bool]$snapshot.Enabled) {
                Enable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop | Out-Null
            }
            else {
                Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop | Out-Null
            }
        }
        catch { $errors.Add("Failed to restore legacy IPv6: $($_.Exception.Message)") }
    }

    Write-Host '[4/7] Restoring legacy Edge QUIC policy...'
    try {
        $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        if ([bool]$legacy.QuicPolicyExisted) {
            New-Item -Path $edgePolicyPath -Force | Out-Null
            New-ItemProperty -Path $edgePolicyPath -Name 'QuicAllowed' -PropertyType DWord -Value ([int]$legacy.QuicPolicyValue) -Force | Out-Null
        }
        else {
            Remove-ItemProperty -Path $edgePolicyPath -Name 'QuicAllowed' -ErrorAction SilentlyContinue
        }
    }
    catch { $errors.Add("Failed to restore legacy Edge QUIC: $($_.Exception.Message)") }

    Write-Host '[5/7] Stopping legacy tun2socks...'
    if ($layout -and $legacy.TunPid) {
        Stop-TTOwnedProcess -ProcessId ([int]$legacy.TunPid) -ExpectedPath $layout.TunExe -Errors $errors
    }
    Start-Sleep -Milliseconds 800

    Write-Host '[6/7] Removing legacy bridge routes...'
    foreach ($entry in @($legacy.BridgeRoutes)) {
        if (-not $entry -or -not [bool]$entry.CreatedByScript) { continue }
        try {
            $adapter = Find-TTAdapterByGuid -GuidText ([string]$legacy.PhysicalGuid)
            if (-not $adapter) { throw 'Original legacy Internet adapter is unavailable.' }
            Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "$($entry.IP)/32" -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceIndex -eq $adapter.ifIndex -and $_.NextHop -eq [string]$legacy.Gateway } |
                Remove-NetRoute -Confirm:$false -ErrorAction Stop
        }
        catch { $errors.Add("Failed to remove legacy bridge route $($entry.IP): $($_.Exception.Message)") }
    }

    Write-Host '[7/7] Stopping legacy Tor and flushing DNS...'
    if ($layout -and $legacy.TorPid) {
        Stop-TTOwnedProcess -ProcessId ([int]$legacy.TorPid) -ExpectedPath $layout.TorExe -Errors $errors
    }
    try { & ipconfig.exe /flushdns | Out-Null } catch {}

    if ($errors.Count -eq 0) {
        Remove-Item -LiteralPath $legacyStateFile -Force -ErrorAction SilentlyContinue
        Write-Host ''
        Write-Host 'Legacy v2.1 session was restored cleanly. You may now use the current TorTunnel version.' -ForegroundColor Green
        Pause-IfRequested
        exit 0
    }
    else {
        Write-Host ''
        Write-Host 'Legacy restoration has warnings; the old state file was kept:' -ForegroundColor Red
        foreach ($item in $errors) { Write-Host " - $item" -ForegroundColor Red }
        Pause-IfRequested
        exit 1
    }
}

Write-Host 'No v3.x or v2.1 saved state was found.' -ForegroundColor Yellow
Write-Host 'The remaining mode is a best-effort reset for the earlier MANUAL commands.' -ForegroundColor Yellow
Write-Host 'It may reset DNS on the current Internet adapter to automatic/DHCP.' -ForegroundColor Yellow
$answer = Read-Host 'Continue with manual reset? Type YES'
if ($answer -ne 'YES') { exit 0 }

# Remove manual /1 routes attached to tun2socks adapters.
$tunAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -eq 'tun2socks Tunnel' })
$tunIndices = @($tunAdapters | ForEach-Object { [int]$_.ifIndex })
foreach ($prefix in @('0.0.0.0/1','128.0.0.0/1')) {
    Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue |
        Where-Object { $tunIndices -contains [int]$_.InterfaceIndex } |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
}

try {
    $layout = Resolve-TTLayout -Root $Root
    foreach ($nameAndPath in @(
        [pscustomobject]@{ Name='tun2socks.exe'; Path=$layout.TunExe },
        [pscustomobject]@{ Name='tor.exe'; Path=$layout.TorExe }
    )) {
        $procs = Get-CimInstance Win32_Process -Filter "Name='$($nameAndPath.Name)'" -ErrorAction SilentlyContinue
        foreach ($proc in $procs) {
            if ($proc.ExecutablePath -and [string]::Equals([IO.Path]::GetFullPath($proc.ExecutablePath),[IO.Path]::GetFullPath($nameAndPath.Path),[StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
catch {}

Get-NetFirewallRule -Group 'TorTunnel' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Get-NetFirewallRule -Group 'TorTunnel Universal' -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'QuicAllowed' -ErrorAction SilentlyContinue

try {
    $primary = Get-TTPrimaryIPv4
    Set-DnsClientServerAddress -InterfaceIndex $primary.Adapter.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue
    Enable-NetAdapterBinding -Name $primary.Adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Reset DNS/IPv6 on current Internet adapter: $($primary.Adapter.Name)"
}
catch { Write-Warning 'Could not auto-restore DNS/IPv6 on the current Internet adapter.' }

try { & ipconfig.exe /flushdns | Out-Null } catch {}
Write-Host ''
Write-Host 'Manual reset completed. Confirm normal Internet access before running Start.' -ForegroundColor Green
Write-Host 'If you used custom static DNS before the manual setup, reapply your custom DNS now.'
Pause-IfRequested
