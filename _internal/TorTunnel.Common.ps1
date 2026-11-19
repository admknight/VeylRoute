# TorTunnel.Common.ps1
# Shared functions for TorTunnel Universal. Product version is read from VERSION.txt.
# Requires Windows PowerShell 5.1+ on Windows 10/11.

Set-StrictMode -Version 2.0

function Test-TTAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TTRoot {
    param([Parameter(Mandatory=$true)][string]$ScriptRoot)
    return [IO.Path]::GetFullPath($ScriptRoot.TrimEnd('\\'))
}

function Get-TTVersion {
    param([Parameter(Mandatory=$true)][string]$Root)
    $versionPath = Join-Path $Root 'VERSION.txt'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw "Missing VERSION.txt: $versionPath"
    }
    $firstLine = [string](Get-Content -LiteralPath $versionPath -ErrorAction Stop | Select-Object -First 1)
    if ($firstLine -match 'v(?<ver>\d+\.\d+\.\d+)') {
        return ('v' + $Matches['ver'])
    }
    throw 'VERSION.txt does not contain a valid semantic version such as vX.Y.Z.'
}

function Get-TTVersionNumber {
    param([Parameter(Mandatory=$true)][string]$Root)
    return (Get-TTVersion -Root $Root).TrimStart('v')
}

function Get-TTProductCredits {
    return [pscustomobject]@{
        Author  = 'Adam Knight'
        Company = ''
        Email   = 'https://github.com/admknight/VeylRoute/issues'
        Phone   = 'GitHub Issues'
    }
}



function Get-TTMachineGuid {
    try {
        return [string](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop)
    }
    catch {
        return [string]([Environment]::MachineName)
    }
}

function Write-TTUtf8NoBom {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Save-TTJson {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Path
    )
    $json = $Object | ConvertTo-Json -Depth 12
    Write-TTUtf8NoBom -Path $Path -Text $json
}

function Get-TTSettings {
    param([Parameter(Mandatory=$true)][string]$Root)

    $path = Join-Path $Root 'config\settings.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing settings file: $path"
    }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Could not read settings.json: $($_.Exception.Message)"
    }

    function Read-Setting([string]$Name, $Default) {
        $prop = $raw.PSObject.Properties[$Name]
        if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
        return $prop.Value
    }

    $settings = [pscustomobject]@{
        ExitCountry             = ([string](Read-Setting 'ExitCountry' 'us')).ToLowerInvariant()
        ExitCountries           = @((Read-Setting 'ExitCountries' @()))
        ExitUsePool             = [bool](Read-Setting 'ExitUsePool' $false)
        StrictExitCountry       = [bool](Read-Setting 'StrictExitCountry' $false)
        RoutingMode             = 'systemwide'  # session-only; Start overrides after prompting
        SelectedAppsDns         = ([string](Read-Setting 'SelectedAppsDns' 'system')).ToLowerInvariant()
        TorAppKillSwitch        = [bool](Read-Setting 'TorAppKillSwitch' $true)
        BlockTorAppUdp          = [bool](Read-Setting 'BlockTorAppUdp' $true)
        EnableSelectedTorApps   = [bool](Read-Setting 'EnableSelectedTorApps' $true)
        SocksPort               = [int](Read-Setting 'SocksPort' 9050)
        DnsMode                 = ([string](Read-Setting 'DnsMode' 'doh')).ToLowerInvariant()
        DohPrimary              = [string](Read-Setting 'DohPrimary' '1.1.1.1')
        DohSecondary            = [string](Read-Setting 'DohSecondary' '1.0.0.1')
        DohTemplate             = [string](Read-Setting 'DohTemplate' 'https://cloudflare-dns.com/dns-query')
        BlockPlainDns           = [bool](Read-Setting 'BlockPlainDns' $true)
        BootstrapTimeoutSeconds = [int](Read-Setting 'BootstrapTimeoutSeconds' 240)
        RouteMetric             = [int](Read-Setting 'RouteMetric' 5)
        TransparentProbeAttempts = [int](Read-Setting 'TransparentProbeAttempts' 3)
        TransparentProbeDelaySeconds = [int](Read-Setting 'TransparentProbeDelaySeconds' 3)
        DisableIPv6             = [bool](Read-Setting 'DisableIPv6' $true)
        DisableEdgeQuic         = [bool](Read-Setting 'DisableEdgeQuic' $true)
        EdgeKillSwitch          = [bool](Read-Setting 'EdgeKillSwitch' $true)
        OpenEdgeAfterConnect    = [bool](Read-Setting 'OpenEdgeAfterConnect' $false)
        FreshTorStateOnNewPC    = [bool](Read-Setting 'FreshTorStateOnNewPC' $true)
        EnableAppExclusions     = [bool](Read-Setting 'EnableAppExclusions' $true)
    }

    if ($settings.ExitCountry -notmatch '^[a-z]{2}$') {
        throw 'ExitCountry must be a two-letter ISO country code such as us.'
    }
    $allowed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @($settings.ExitCountries)) {
        $code = ([string]$entry).Trim().ToLowerInvariant()
        if ($code -notmatch '^[a-z]{2}$') { throw ('ExitCountries has invalid country code: ' + $code) }
        if (-not $allowed.Contains($code)) { $allowed.Add($code) }
    }
    if ($settings.ExitUsePool -and $allowed.Count -eq 0) { throw 'ExitUsePool requires at least one ExitCountries entry.' }
    if ($settings.ExitUsePool) { $settings.ExitCountries = [string[]]$allowed.ToArray() }
    else { $settings.ExitCountries = @($settings.ExitCountry) }
    if ($settings.SelectedAppsDns -ne 'system') {
        throw 'SelectedAppsDns must be system for the current SelectedAppsOnly implementation. Selected-app mode intentionally leaves Windows DNS on the normal connection.'
    }
    if ($settings.SocksPort -lt 1 -or $settings.SocksPort -gt 65535) {
        throw 'SocksPort must be between 1 and 65535.'
    }
    if ($settings.DnsMode -ne 'doh') {
        throw 'DnsMode must be doh for the current SystemWide implementation.'
    }
    foreach ($server in @($settings.DohPrimary,$settings.DohSecondary)) {
        $parsed = $null
        if (-not [Net.IPAddress]::TryParse($server,[ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw "DoH resolver must be an IPv4 address: $server"
        }
    }
    if (-not $settings.DohTemplate.StartsWith('https://',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'DohTemplate must be an https:// URL.'
    }
    if ($settings.BootstrapTimeoutSeconds -lt 30 -or $settings.BootstrapTimeoutSeconds -gt 900) {
        throw 'BootstrapTimeoutSeconds must be between 30 and 900.'
    }
    if ($settings.TransparentProbeAttempts -lt 1 -or $settings.TransparentProbeAttempts -gt 6) { throw 'TransparentProbeAttempts must be 1 through 6.' }
    if ($settings.TransparentProbeDelaySeconds -lt 1 -or $settings.TransparentProbeDelaySeconds -gt 20) { throw 'TransparentProbeDelaySeconds must be 1 through 20.' }
    if ($settings.RouteMetric -lt 1 -or $settings.RouteMetric -gt 9999) {
        throw 'RouteMetric must be between 1 and 9999.'
    }

    return $settings
}

function Find-TTFirstExistingFile {
    param([string[]]$Candidates)
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return [IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Resolve-TTLayout {
    param([Parameter(Mandatory=$true)][string]$Root)

    $torRoot = Join-Path $Root 'Tor'
    $tunRoot = Join-Path $Root 'tun2socks'

    $torExe = Find-TTFirstExistingFile @(
        (Join-Path $torRoot 'tor\tor.exe'),
        (Join-Path $torRoot 'tor.exe')
    )
    if (-not $torExe -and (Test-Path -LiteralPath $torRoot)) {
        $torExe = Get-ChildItem -LiteralPath $torRoot -Filter 'tor.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }

    $lyrebird = Find-TTFirstExistingFile @(
        (Join-Path $torRoot 'tor\pluggable_transports\lyrebird.exe'),
        (Join-Path $torRoot 'pluggable_transports\lyrebird.exe')
    )
    if (-not $lyrebird -and (Test-Path -LiteralPath $torRoot)) {
        $lyrebird = Get-ChildItem -LiteralPath $torRoot -Filter 'lyrebird.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }

    $geoip = Find-TTFirstExistingFile @(
        (Join-Path $torRoot 'data\geoip'),
        (Join-Path $torRoot 'geoip')
    )
    if (-not $geoip -and (Test-Path -LiteralPath $torRoot)) {
        $geoip = Get-ChildItem -LiteralPath $torRoot -Filter 'geoip' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }

    $geoip6 = Find-TTFirstExistingFile @(
        (Join-Path $torRoot 'data\geoip6'),
        (Join-Path $torRoot 'geoip6')
    )
    if (-not $geoip6 -and (Test-Path -LiteralPath $torRoot)) {
        $geoip6 = Get-ChildItem -LiteralPath $torRoot -Filter 'geoip6' -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
    }

    $tunExe = Find-TTFirstExistingFile @(
        (Join-Path $tunRoot 'tun2socks.exe')
    )
    $wintunDll = Find-TTFirstExistingFile @(
        (Join-Path $tunRoot 'wintun.dll')
    )

    $missing = New-Object 'System.Collections.Generic.List[string]'
    if (-not $torExe) { $missing.Add('Tor executable (Tor\tor\tor.exe or Tor\tor.exe)') }
    if (-not $lyrebird) { $missing.Add('lyrebird.exe') }
    if (-not $geoip) { $missing.Add('geoip') }
    if (-not $geoip6) { $missing.Add('geoip6') }
    if (-not $tunExe) { $missing.Add('tun2socks\tun2socks.exe') }
    if (-not $wintunDll) { $missing.Add('tun2socks\wintun.dll') }

    if ($missing.Count -gt 0) {
        throw ('Required portable component(s) missing: ' + ($missing -join ', '))
    }

    return [pscustomobject]@{
        TorExe    = [IO.Path]::GetFullPath($torExe)
        Lyrebird  = [IO.Path]::GetFullPath($lyrebird)
        GeoIP     = [IO.Path]::GetFullPath($geoip)
        GeoIP6    = [IO.Path]::GetFullPath($geoip6)
        TunDir    = [IO.Path]::GetFullPath($tunRoot)
        TunExe    = [IO.Path]::GetFullPath($tunExe)
        WintunDll = [IO.Path]::GetFullPath($wintunDll)
    }
}

function Get-TTBridgeConfig {
    param([Parameter(Mandatory=$true)][string]$Root)

    $configDir = Join-Path $Root 'config'
    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }

    $bridgeFile = Join-Path $configDir 'bridges.txt'
    $rawLines = @()
    if (Test-Path -LiteralPath $bridgeFile) {
        $rawLines = @(Get-Content -LiteralPath $bridgeFile -ErrorAction Stop)
    }

    $usable = @($rawLines | Where-Object { $_ -and $_.Trim() -and -not $_.Trim().StartsWith('#') })

    if ($usable.Count -eq 0) {
        $legacyCandidates = @(
            (Join-Path $Root 'Tor\torrc'),
            (Join-Path $Root 'torrc')
        )
        foreach ($legacy in $legacyCandidates) {
            if (Test-Path -LiteralPath $legacy) {
                $legacyLines = @(Get-Content -LiteralPath $legacy -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match '^\s*Bridge\s+obfs4\s+' })
                if ($legacyLines.Count -gt 0) {
                    $usable = $legacyLines
                    Write-TTUtf8NoBom -Path $bridgeFile -Text (($legacyLines -join "`r`n") + "`r`n")
                    break
                }
            }
        }
    }

    if ($usable.Count -eq 0) {
        throw "No obfs4 bridges were found. Put one or more bridge lines in: $bridgeFile"
    }

    $normalized = New-Object 'System.Collections.Generic.List[string]'
    $ips = New-Object 'System.Collections.Generic.List[string]'

    foreach ($rawLine in $usable) {
        $line = $rawLine.Trim()
        if ($line -match '^obfs4\s+') {
            $line = 'Bridge ' + $line
        }
        if ($line -notmatch '^Bridge\s+obfs4\s+') {
            throw "Unsupported bridge line in bridges.txt. This build expects obfs4: $rawLine"
        }

        $match = [regex]::Match($line, '^Bridge\s+obfs4\s+((?:\d{1,3}\.){3}\d{1,3}):(\d+)\s+')
        if (-not $match.Success) {
            throw "Could not parse the IPv4 obfs4 bridge address: $rawLine"
        }

        $ipText = $match.Groups[1].Value
        $port = [int]$match.Groups[2].Value
        $parsed = $null
        if (-not [Net.IPAddress]::TryParse($ipText, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw "Invalid IPv4 bridge address: $ipText"
        }
        if ($port -lt 1 -or $port -gt 65535) {
            throw "Invalid bridge port in line: $rawLine"
        }

        $normalized.Add($line)
        if (-not $ips.Contains($ipText)) { $ips.Add($ipText) }
    }

    return [pscustomobject]@{
        File  = $bridgeFile
        Lines = [string[]]$normalized.ToArray()
        IPs   = [string[]]$ips.ToArray()
    }
}

function ConvertTo-TTTorQuotedPath {
    param([Parameter(Mandatory=$true)][string]$Path)

    # Tor's configuration parser accepts C-style escapes inside quoted values.
    # On Windows, Tor's absolute-path test expects a drive path using backslashes
    # (for example C:\\TorTunnel\\runtime), not C:/TorTunnel/runtime.
    # Double the backslashes for the quoted torrc value so Tor decodes them back
    # to normal Windows path separators. This also keeps paths with spaces portable.
    $p = [IO.Path]::GetFullPath($Path)
    $p = $p.Replace('\','\\')
    $p = $p.Replace('"','\"')
    return '"' + $p + '"'
}


function Get-TTTorPtExecSpec {
    param([Parameter(Mandatory=$true)][string]$LyrebirdPath)

    $source = [IO.Path]::GetFullPath($LyrebirdPath)

    # IMPORTANT: ClientTransportPlugin's `exec` value is not parsed like normal
    # quoted torrc path options on Windows. Passing a C-style quoted path here can
    # leave literal quote characters in the executable name and make CreateProcess
    # fail. Use a plain, unquoted executable path whenever possible.
    if ($source -notmatch '\s') {
        return [pscustomobject]@{
            SourcePath   = $source
            ExecPath     = $source
            ShimRequired = $false
        }
    }

    # If the portable TorTunnel folder itself contains spaces, use a tiny runtime
    # copy of lyrebird at a guaranteed no-space path on the Windows system drive.
    # This keeps the overall package portable without relying on 8.3 short names,
    # which may be disabled on some NTFS volumes.
    $systemDrive = [string]$env:SystemDrive
    if ([string]::IsNullOrWhiteSpace($systemDrive)) {
        $systemDrive = [IO.Path]::GetPathRoot([Environment]::SystemDirectory).TrimEnd('\\')
    }
    $shimDir = Join-Path $systemDrive 'TorTunnelPT'
    $shimPath = Join-Path $shimDir 'lyrebird.exe'
    if ($shimPath -match '\s') {
        throw "Could not create a no-space pluggable-transport path. Move TorTunnel to a path without spaces. Source: $source"
    }

    return [pscustomobject]@{
        SourcePath   = $source
        ExecPath     = $shimPath
        ShimRequired = $true
    }
}

function Install-TTTorPtExecShim {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$ExecPath,
        [Parameter(Mandatory=$true)][bool]$Required
    )

    if (-not $Required) { return }
    $dir = Split-Path -Parent $ExecPath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -LiteralPath $SourcePath -Destination $ExecPath -Force -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $ExecPath -PathType Leaf)) {
        throw "Could not stage lyrebird at: $ExecPath"
    }
}

function Initialize-TTRuntimeForMachine {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)]$Settings
    )

    $runtime = Join-Path $Root 'runtime'
    if (-not (Test-Path -LiteralPath $runtime)) {
        New-Item -Path $runtime -ItemType Directory -Force | Out-Null
    }

    $machineGuid = Get-TTMachineGuid
    $marker = Join-Path $runtime 'machine.id'
    $oldMachine = $null
    if (Test-Path -LiteralPath $marker) {
        try { $oldMachine = (Get-Content -LiteralPath $marker -Raw -ErrorAction Stop).Trim() } catch {}
    }

    if ($oldMachine -and $oldMachine -ne $machineGuid) {
        Write-Host "This portable folder was last used on another PC. Clearing machine-specific runtime state..." -ForegroundColor Yellow
        Remove-Item -LiteralPath (Join-Path $runtime 'session-state.json') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $runtime 'torrc.generated') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $runtime 'tor.log') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $runtime 'tun2socks.out.log') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $runtime 'tun2socks.err.log') -Force -ErrorAction SilentlyContinue
        if ($Settings.FreshTorStateOnNewPC) {
            Remove-Item -LiteralPath (Join-Path $runtime 'tor-data') -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Write-TTUtf8NoBom -Path $marker -Text ($machineGuid + "`r`n")
    return [pscustomobject]@{
        RuntimeDir  = $runtime
        MachineGuid = $machineGuid
        StateFile   = (Join-Path $runtime 'session-state.json')
    }
}

function New-TTGeneratedTorrc {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)]$Layout,
        [Parameter(Mandatory=$true)]$Settings,
        [Parameter(Mandatory=$true)]$BridgeConfig
    )

    $runtime = Join-Path $Root 'runtime'
    $torData = Join-Path $runtime 'tor-data'
    if (-not (Test-Path -LiteralPath $torData)) {
        New-Item -Path $torData -ItemType Directory -Force | Out-Null
    }

    $torrc = Join-Path $runtime 'torrc.generated'
    $log = Join-Path $runtime 'tor.log'

    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('# Generated by TorTunnel Universal. Manual edits are overwritten.')
    $lines.Add('ClientOnly 1')
    $lines.Add("SocksPort 127.0.0.1:$($Settings.SocksPort)")
    $lines.Add('DataDirectory ' + (ConvertTo-TTTorQuotedPath $torData))
    # New Circuit uses an ephemeral loopback control port with SAFECOOKIE authentication.
    # Never expose an unauthenticated listener or a fixed public control endpoint.
    $controlPortFile = Join-Path $runtime 'tor-control.port'
    $controlCookieFile = Join-Path $torData 'control_auth_cookie'
    Remove-Item -LiteralPath $controlPortFile -Force -ErrorAction SilentlyContinue
    $lines.Add('ControlPort auto')
    $lines.Add('ControlPortWriteToFile ' + (ConvertTo-TTTorQuotedPath $controlPortFile))
    $lines.Add('CookieAuthentication 1')
    $lines.Add('CookieAuthFile ' + (ConvertTo-TTTorQuotedPath $controlCookieFile))
    $lines.Add('GeoIPFile ' + (ConvertTo-TTTorQuotedPath $Layout.GeoIP))
    $lines.Add('GeoIPv6File ' + (ConvertTo-TTTorQuotedPath $Layout.GeoIP6))
    $exitNodeList = @($Settings.ExitCountries | ForEach-Object { '{' + [string]$_ + '}' }) -join ','
    $lines.Add('ExitNodes ' + $exitNodeList)
    $lines.Add('UseBridges 1')
    $ptExec = Get-TTTorPtExecSpec -LyrebirdPath $Layout.Lyrebird
    $lines.Add('ClientTransportPlugin obfs4 exec ' + $ptExec.ExecPath)
    foreach ($bridge in $BridgeConfig.Lines) { $lines.Add([string]$bridge) }
    $lines.Add('Log notice file ' + (ConvertTo-TTTorQuotedPath $log))

    Write-TTUtf8NoBom -Path $torrc -Text (($lines -join "`r`n") + "`r`n")

    return [pscustomobject]@{
        Torrc          = $torrc
        TorData        = $torData
        ControlPortFile = $controlPortFile
        ControlCookieFile = $controlCookieFile
        Log            = $log
        PtSourcePath   = $ptExec.SourcePath
        PtExecPath     = $ptExec.ExecPath
        PtShimRequired = [bool]$ptExec.ShimRequired
    }
}

function Test-TTRootWritable {
    param([Parameter(Mandatory=$true)][string]$Root)
    if ($Root.StartsWith('\\')) {
        throw 'Run TorTunnel from a local drive, not a UNC/network-share path.'
    }
    $probe = Join-Path $Root ('.tt-write-test-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($probe, 'test')
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
    catch {
        throw "The TorTunnel folder is not writable: $Root"
    }
}

function Get-TTNativeArchitecture {
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        switch ([int]$cpu.Architecture) {
            9  { return 'x64' }
            12 { return 'arm64' }
            0  { return 'x86' }
            default { return "unknown-$($cpu.Architecture)" }
        }
    }
    catch {
        if ([Environment]::Is64BitOperatingSystem) { return 'x64-or-arm64' }
        return 'x86'
    }
}

function Get-TTPrimaryIPv4 {
    $routes = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop |
        Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' -and $_.InterfaceAlias -notmatch 'wintun|tun2socks' })

    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($route in $routes) {
        $adapter = Get-NetAdapter -IncludeHidden -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        $ipif = Get-NetIPInterface -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        if (-not $adapter -or -not $ipif) { continue }
        if ($adapter.Status -ne 'Up' -or $ipif.ConnectionState -ne 'Connected') { continue }

        $hardwarePenalty = 0
        try { if (-not [bool]$adapter.HardwareInterface) { $hardwarePenalty = 5000 } } catch {}
        $score = [int]$route.RouteMetric + [int]$ipif.InterfaceMetric + $hardwarePenalty
        $items.Add([pscustomobject]@{ Route=$route; Adapter=$adapter; Score=$score })
    }

    $best = $items | Sort-Object Score | Select-Object -First 1
    if (-not $best) {
        throw 'No active IPv4 Internet/default route was found. Connect Wi-Fi or Ethernet first.'
    }
    return $best
}

function Get-TTRelevantAdapters {
    param([Parameter(Mandatory=$true)]$PrimaryAdapter)

    $byGuid = @{}
    function Add-Adapter($Adapter) {
        if (-not $Adapter) { return }
        if ($Adapter.Name -match 'wintun|tun2socks') { return }
        $guid = ([guid]$Adapter.InterfaceGuid).ToString('B')
        if (-not $byGuid.ContainsKey($guid)) { $byGuid[$guid] = $Adapter }
    }

    Add-Adapter $PrimaryAdapter

    $defaultRoutes = @()
    $defaultRoutes += @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue)
    $defaultRoutes += @(Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue)
    foreach ($route in $defaultRoutes) {
        $adapter = Get-NetAdapter -IncludeHidden -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue
        if ($adapter -and $adapter.Status -eq 'Up') { Add-Adapter $adapter }
    }

    return @($byGuid.GetEnumerator() | ForEach-Object { $_.Value })
}

function Get-TTDnsSnapshot {
    param([Parameter(Mandatory=$true)]$Adapter)

    $guidText = ([guid]$Adapter.InterfaceGuid).ToString('B')
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guidText"
    $nameServer = $null
    try {
        $nameServer = (Get-ItemProperty -Path $regPath -Name 'NameServer' -ErrorAction SilentlyContinue).NameServer
    }
    catch {}

    $servers = @()
    try {
        $servers = @((Get-DnsClientServerAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
    }
    catch {}

    return [pscustomobject]@{
        InterfaceGuid  = $guidText
        InterfaceAlias = [string]$Adapter.Name
        WasDhcp        = [string]::IsNullOrWhiteSpace([string]$nameServer)
        Servers        = $servers
    }
}

function Get-TTIPv6BindingSnapshot {
    param([Parameter(Mandatory=$true)]$Adapter)
    $binding = Get-NetAdapterBinding -Name $Adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    if (-not $binding) { return $null }
    return [pscustomobject]@{
        InterfaceGuid  = ([guid]$Adapter.InterfaceGuid).ToString('B')
        InterfaceAlias = [string]$Adapter.Name
        Enabled        = [bool]$binding.Enabled
    }
}

function Find-TTAdapterByGuid {
    param([Parameter(Mandatory=$true)][string]$GuidText)
    return Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Where-Object { ([guid]$_.InterfaceGuid).ToString('B') -eq $GuidText } |
        Select-Object -First 1
}

function Get-TTEdgeExecutable {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe'
    )
    foreach ($path in $registryPaths) {
        try {
            $item = Get-Item -Path $path -ErrorAction Stop
            $value = [string]$item.GetValue('')
            if ($value -and (Test-Path -LiteralPath $value)) { return [IO.Path]::GetFullPath($value) }
        }
        catch {}
    }

    $candidates = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return [IO.Path]::GetFullPath($candidate) }
    }
    return $null
}

function Invoke-TTCurlText {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)

    # curl failures (timeouts, temporary Tor bootstrap unavailability, etc.) are
    # expected probes in several retry loops.  Do not let native stderr become
    # a terminating PowerShell error when the caller has ErrorActionPreference=Stop.
    $oldErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        $output = & curl.exe @Arguments 2>$null
        $exitCode = $LASTEXITCODE
    }
    catch {
        return $null
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
    }

    if ($exitCode -ne 0 -or $null -eq $output) { return $null }
    return (($output -join "`n").Trim())
}

function Get-TTTorBootstrapStatus {
    param([Parameter(Mandatory=$true)][string]$LogPath)

    $result = [pscustomobject]@{
        Percent = 0
        Done    = $false
        Line    = $null
    }

    if (-not (Test-Path -LiteralPath $LogPath)) { return $result }

    $lines = @(Get-Content -LiteralPath $LogPath -Tail 120 -ErrorAction SilentlyContinue)
    $last = $lines | Where-Object { $_ -match 'Bootstrapped\s+(\d+)%' } | Select-Object -Last 1
    if (-not $last) { return $result }

    $m = [regex]::Match([string]$last, 'Bootstrapped\s+(\d+)%')
    if ($m.Success) {
        $result.Percent = [int]$m.Groups[1].Value
        $result.Done = ($result.Percent -ge 100)
        $result.Line = [string]$last
    }
    return $result
}

function Get-TTTorCheckViaSocks {
    param([Parameter(Mandatory=$true)][int]$SocksPort)
    $text = Invoke-TTCurlText @(
        '--silent','--show-error','--max-time','15',
        '--socks5-hostname',"127.0.0.1:$SocksPort",
        'https://check.torproject.org/api/ip'
    )
    if (-not $text) { return $null }
    try {
        $obj = $text | ConvertFrom-Json
        if ($obj.IsTor) { return $obj }
    }
    catch {}
    return $null
}

function Test-TTTcpPort {
    param([string]$HostName='127.0.0.1',[int]$Port,[int]$TimeoutMs=700)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if (-not $task.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    }
    catch { return $false }
    finally { $client.Dispose() }
}

function Get-TTDnsPortConflict {
    param([Parameter(Mandatory=$true)]$Settings)

    $endpoints = @(Get-NetUDPEndpoint -LocalPort $Settings.DnsPort -ErrorAction SilentlyContinue)
    if ($endpoints.Count -lt 1) { return @() }

    $results = @()
    $owners = @($endpoints | Select-Object -ExpandProperty OwningProcess -Unique)
    foreach ($ownerProcessId in $owners) {
        $ownerProcess = Get-Process -Id $ownerProcessId -ErrorAction SilentlyContinue
        $services = @(Get-CimInstance Win32_Service -Filter "ProcessId = $ownerProcessId" -ErrorAction SilentlyContinue)
        $serviceNames = @($services | ForEach-Object { [string]$_.Name } | Where-Object { $_ })
        $serviceDisplayNames = @($services | ForEach-Object { [string]$_.DisplayName } | Where-Object { $_ })
        $results += [pscustomobject]@{
            ProcessId           = [int]$ownerProcessId
            ProcessName         = if ($ownerProcess) { [string]$ownerProcess.ProcessName } else { $null }
            ServiceNames        = $serviceNames
            ServiceDisplayNames = $serviceDisplayNames
        }
    }
    return @($results)
}

function Test-TTDnsConflictIsSharedAccess {
    param([Parameter(Mandatory=$true)][object[]]$Conflict)

    if ($Conflict.Count -lt 1) { return $false }
    foreach ($entry in $Conflict) {
        if (-not (@($entry.ServiceNames) -contains 'SharedAccess')) { return $false }
    }
    return $true
}

function Format-TTDnsPortConflict {
    param([Parameter(Mandatory=$true)][object[]]$Conflict)

    $items = @()
    foreach ($entry in $Conflict) {
        $label = if ($entry.ProcessName) { "$($entry.ProcessName) (PID $($entry.ProcessId))" } else { "PID $($entry.ProcessId)" }
        $services = @($entry.ServiceNames)
        if ($services.Count -gt 0) { $label += ' [' + ($services -join ', ') + ']' }
        $items += $label
    }
    return ($items -join ', ')
}

function Assert-TTPortsFree {
    param([Parameter(Mandatory=$true)]$Settings)

    $tcp = Get-NetTCPConnection -LocalPort $Settings.SocksPort -State Listen -ErrorAction SilentlyContinue
    if ($tcp) {
        throw "TCP port $($Settings.SocksPort) is already in use. Stop the program using it before Start."
    }
}

function Assert-TTDohSupport {
    $required = @(
        'Get-DnsClientDohServerAddress',
        'Add-DnsClientDohServerAddress',
        'Set-DnsClientDohServerAddress',
        'Remove-DnsClientDohServerAddress'
    )
    foreach ($name in $required) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
            throw "Windows DNS-over-HTTPS support is unavailable: missing $name. Use a current Windows 10/11 build."
        }
    }
}

function Get-TTDohSnapshot {
    param([Parameter(Mandatory=$true)]$Settings)

    Assert-TTDohSupport
    $items = @()
    foreach ($server in @($Settings.DohPrimary,$Settings.DohSecondary)) {
        $entry = Get-DnsClientDohServerAddress -ServerAddress $server -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($entry) {
            $items += [pscustomobject]@{
                ServerAddress      = [string]$server
                Existed            = $true
                DohTemplate        = [string]$entry.DohTemplate
                AutoUpgrade        = [bool]$entry.AutoUpgrade
                AllowFallbackToUdp = [bool]$entry.AllowFallbackToUdp
            }
        }
        else {
            $items += [pscustomobject]@{
                ServerAddress      = [string]$server
                Existed            = $false
                DohTemplate        = $null
                AutoUpgrade        = $false
                AllowFallbackToUdp = $false
            }
        }
    }
    return $items
}

function Set-TTStrictDoh {
    param([Parameter(Mandatory=$true)]$Settings)

    Assert-TTDohSupport
    foreach ($server in @($Settings.DohPrimary,$Settings.DohSecondary)) {
        $entry = Get-DnsClientDohServerAddress -ServerAddress $server -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($entry) {
            Set-DnsClientDohServerAddress -ServerAddress $server -DohTemplate $Settings.DohTemplate -AutoUpgrade $true -AllowFallbackToUdp $false -Confirm:$false -ErrorAction Stop | Out-Null
        }
        else {
            Add-DnsClientDohServerAddress -ServerAddress $server -DohTemplate $Settings.DohTemplate -AutoUpgrade $true -AllowFallbackToUdp $false -Confirm:$false -ErrorAction Stop | Out-Null
        }
    }

    if (-not (Test-TTStrictDohConfiguration -Settings $Settings)) {
        throw 'Windows did not retain the requested strict DNS-over-HTTPS configuration.'
    }
}

function Test-TTStrictDohConfiguration {
    param([Parameter(Mandatory=$true)]$Settings)

    try {
        Assert-TTDohSupport
        foreach ($server in @($Settings.DohPrimary,$Settings.DohSecondary)) {
            $entry = Get-DnsClientDohServerAddress -ServerAddress $server -ErrorAction Stop | Select-Object -First 1
            if (-not $entry) { return $false }
            if (-not [bool]$entry.AutoUpgrade) { return $false }
            if ([bool]$entry.AllowFallbackToUdp) { return $false }
            if ([string]$entry.DohTemplate -ne [string]$Settings.DohTemplate) { return $false }
        }
        return $true
    }
    catch { return $false }
}

function Restore-TTDohSnapshot {
    param([Parameter(Mandatory=$true)][object[]]$Snapshot)

    Assert-TTDohSupport
    foreach ($saved in $Snapshot) {
        if (-not $saved -or -not $saved.ServerAddress) { continue }
        $server = [string]$saved.ServerAddress
        $current = Get-DnsClientDohServerAddress -ServerAddress $server -ErrorAction SilentlyContinue | Select-Object -First 1
        if ([bool]$saved.Existed) {
            if ($current) {
                Set-DnsClientDohServerAddress -ServerAddress $server -DohTemplate ([string]$saved.DohTemplate) -AutoUpgrade ([bool]$saved.AutoUpgrade) -AllowFallbackToUdp ([bool]$saved.AllowFallbackToUdp) -Confirm:$false -ErrorAction Stop | Out-Null
            }
            else {
                Add-DnsClientDohServerAddress -ServerAddress $server -DohTemplate ([string]$saved.DohTemplate) -AutoUpgrade ([bool]$saved.AutoUpgrade) -AllowFallbackToUdp ([bool]$saved.AllowFallbackToUdp) -Confirm:$false -ErrorAction Stop | Out-Null
            }
        }
        elseif ($current) {
            Remove-DnsClientDohServerAddress -ServerAddress $server -Confirm:$false -ErrorAction Stop | Out-Null
        }
    }
}

function Select-TTTunIPv4 {
    $candidates = @('198.18.0.1','198.19.0.1','192.168.123.1','10.254.254.1')
    foreach ($candidate in $candidates) {
        try {
            $result = @(Find-NetRoute -RemoteIPAddress $candidate -ErrorAction Stop)
            $route = $result | Where-Object {
                $_.PSObject.Properties['DestinationPrefix'] -and $_.PSObject.Properties['NextHop']
            } | Select-Object -First 1
            if ($route -and $route.DestinationPrefix -eq '0.0.0.0/0') {
                return $candidate
            }
        }
        catch {
            # Continue to the next candidate. A fallback is handled below.
        }
    }

    # On supported Windows versions Find-NetRoute should be available. If it was not,
    # use the RFC2544 benchmarking range rather than a common home-LAN subnet.
    if (-not (Get-Command Find-NetRoute -ErrorAction SilentlyContinue)) {
        return '198.18.0.1'
    }

    throw 'Could not find a non-conflicting private/benchmark subnet for the Wintun adapter.'
}

function Test-TTManualTunnelRoutes {
    $tunAdapters = @(Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -eq 'tun2socks Tunnel' })
    $indices = @($tunAdapters | ForEach-Object { [int]$_.ifIndex })
    $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.DestinationPrefix -eq '0.0.0.0/1' -or $_.DestinationPrefix -eq '128.0.0.0/1') -and
            ($indices -contains [int]$_.InterfaceIndex)
        })
    return $routes
}

function Stop-TTOwnedProcess {
    param(
        [int]$ProcessId,
        [string]$ExpectedPath,
        [System.Collections.Generic.List[string]]$Errors
    )
    if (-not $ProcessId -or -not $ExpectedPath) { return }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if (-not $proc) { return }
    try {
        $actual = if ($proc.ExecutablePath) { [IO.Path]::GetFullPath([string]$proc.ExecutablePath) } else { $null }
        $expected = [IO.Path]::GetFullPath($ExpectedPath)
        if (-not $actual -or -not [string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase)) {
            $Errors.Add("Refused to stop PID $ProcessId because it is not the expected executable: $actual")
            return
        }
        Stop-Process -Id $ProcessId -Force -ErrorAction Stop
    }
    catch {
        $Errors.Add("Failed to stop process $ProcessId : $($_.Exception.Message)")
    }
}



function ConvertTo-TTIPv4Number {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$IPAddress)

    $parsed = [System.Net.IPAddress]::Parse($IPAddress)
    if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $null
    }

    $bytes = $parsed.GetAddressBytes()
    [Array]::Reverse($bytes)
    return [UInt64]([BitConverter]::ToUInt32($bytes, 0))
}

function Get-TTGeoIpCountry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$IPAddress,
        [Parameter(Mandatory=$true)][string]$GeoIPFile
    )

    if (-not (Test-Path -LiteralPath $GeoIPFile)) { return $null }

    try { $ipNumber = ConvertTo-TTIPv4Number -IPAddress $IPAddress }
    catch { return $null }
    if ($null -eq $ipNumber) { return $null }

    foreach ($line in [System.IO.File]::ReadLines($GeoIPFile)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }

        $parts = $line.Split(',')
        if ($parts.Count -lt 3) { continue }

        $rangeStart = [UInt64]0
        $rangeEnd = [UInt64]0
        if (-not [UInt64]::TryParse($parts[0].Trim().Trim('"'), [ref]$rangeStart)) { continue }
        if (-not [UInt64]::TryParse($parts[1].Trim().Trim('"'), [ref]$rangeEnd)) { continue }

        if ($ipNumber -lt $rangeStart) { break }
        if ($ipNumber -le $rangeEnd) {
            $country = $parts[2].Trim().Trim('"').ToUpperInvariant()
            if ($country) { return $country }
            return $null
        }
    }

    return $null
}

