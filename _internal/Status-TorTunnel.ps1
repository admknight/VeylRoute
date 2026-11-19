[CmdletBinding()]
param([switch]$PauseAtEnd, [string]$Root)
$ErrorActionPreference='Continue'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
. (Join-Path $InternalRoot 'TorTunnel.Common.ps1')
. (Join-Path $InternalRoot 'TorTunnel.AppBypass.ps1')

Write-Host ''
$TTVersion = Get-TTVersion -Root $Root
Write-Host "=== TorTunnel Universal $TTVersion - Status ===" -ForegroundColor Cyan
Write-Host "Portable root      : $Root"
$runtime=Join-Path $Root 'runtime';$stateFile=Join-Path $runtime 'session-state.json'
if(-not(Test-Path -LiteralPath $stateFile)){
    Write-Host 'Session             : DISCONNECTED' -ForegroundColor Yellow
    try{$settings=Get-TTSettings -Root $Root;$ex=@(Get-TTExcludedApps -Root $Root -Settings $settings);$ta=@(Get-TTTorApps -Root $Root -Settings $settings);Write-Host 'Routing mode        : selected during each Start';Write-Host "Configured DIRECT   : $($ex.Count)";Write-Host "Configured TOR apps : $($ta.Count)"}catch{}
    if($PauseAtEnd){[void](Read-Host 'Press Enter to close')};exit 0
}
try{$state=Get-Content -LiteralPath $stateFile -Raw|ConvertFrom-Json -ErrorAction Stop}catch{Write-Host "State               : unreadable - $($_.Exception.Message)" -ForegroundColor Red;if($PauseAtEnd){[void](Read-Host 'Press Enter to close')};exit 1}
if([string]$state.MachineGuid -ne (Get-TTMachineGuid)){Write-Host 'Session             : STALE STATE FROM ANOTHER PC' -ForegroundColor Red;if($PauseAtEnd){[void](Read-Host 'Press Enter to close')};exit 1}
$healthy=$true
$settings=Get-TTSettings -Root $Root
$mode=if($state.PSObject.Properties['RoutingMode']){[string]$state.RoutingMode}else{'systemwide'}
Write-Host 'Session             : state present'
Write-Host "Started             : $($state.StartedAt)"
Write-Host "Routing mode        : $mode"
Write-Host "Internet adapter    : $($state.PhysicalAlias)"
$displayPhysicalIPv4=[string]$state.PhysicalIPv4;if([string]::IsNullOrWhiteSpace($displayPhysicalIPv4)-and $state.PhysicalIndex){try{$displayPhysicalIPv4=Get-TTPrimarySourceIPv4 -InterfaceIndex ([int]$state.PhysicalIndex)}catch{}}
Write-Host "Physical IPv4       : $displayPhysicalIPv4"
Write-Host "Wintun              : $($state.TunName) / ifIndex $($state.TunIndex) / $($state.TunIP)"
$torRunning=$false;if($state.TorPid){$torRunning=[bool](Get-Process -Id ([int]$state.TorPid) -ErrorAction SilentlyContinue)}
Write-Host ('Tor process          : '+$(if($torRunning){'RUNNING'}else{'NOT RUNNING'})) -ForegroundColor $(if($torRunning){'Green'}else{'Red'});if(-not $torRunning){$healthy=$false}
$tunRunning=$false;if($state.TunPid){$tunRunning=[bool](Get-Process -Id ([int]$state.TunPid) -ErrorAction SilentlyContinue)}
Write-Host ('tun2socks process    : '+$(if($tunRunning){'RUNNING'}else{'NOT RUNNING'})) -ForegroundColor $(if($tunRunning){'Green'}else{'Red'});if(-not $tunRunning){$healthy=$false}

$routeCount=0
foreach($prefix in @('0.0.0.0/1','128.0.0.0/1')){if(@(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix $prefix -ErrorAction SilentlyContinue|Where-Object{$_.InterfaceIndex -eq [int]$state.TunIndex}).Count -gt 0){$routeCount++}}
if($mode -eq 'systemwide'){
    Write-Host ('IPv4 /1 routes       : '+$(if($routeCount -eq 2){'PRESENT'}else{"MISSING ($routeCount/2)"})) -ForegroundColor $(if($routeCount -eq 2){'Green'}else{'Red'});if($routeCount -ne 2){$healthy=$false}
}else{
    Write-Host ('System /1 routes     : '+$(if($routeCount -eq 0){'ABSENT (correct)'}else{"UNEXPECTED ($routeCount/2)"})) -ForegroundColor $(if($routeCount -eq 0){'Green'}else{'Red'});if($routeCount -ne 0){$healthy=$false}
}

if($mode -eq 'systemwide'){
    foreach($dns in @($state.DnsBefore)){if(-not $dns){continue};$adapter=Find-TTAdapterByGuid -GuidText ([string]$dns.InterfaceGuid);if($adapter){$servers=@((Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses);$ok=(($servers -contains $settings.DohPrimary)-and($servers -contains $settings.DohSecondary));Write-Host (("DNS $($adapter.Name)").PadRight(20)+': '+($servers -join ', ')) -ForegroundColor $(if($ok){'Green'}else{'Red'});if(-not $ok){$healthy=$false}}}
    if($state.TunIndex){$servers=@((Get-DnsClientServerAddress -InterfaceIndex ([int]$state.TunIndex) -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses);$ok=(($servers -contains $settings.DohPrimary)-and($servers -contains $settings.DohSecondary));Write-Host ('DNS Wintun'.PadRight(20)+': '+($servers -join ', ')) -ForegroundColor $(if($ok){'Green'}else{'Red'});if(-not $ok){$healthy=$false}}
    $dohOk=Test-TTStrictDohConfiguration -Settings $settings;Write-Host ('Strict DoH           : '+$(if($dohOk){'ACTIVE / NO UDP FALLBACK'}else{'NOT ACTIVE'})) -ForegroundColor $(if($dohOk){'Green'}else{'Red'});if(-not $dohOk){$healthy=$false}
    $dnsRules=@();if($state.PSObject.Properties['DnsLeakBlockRules']){$dnsRules=@($state.DnsLeakBlockRules)};if($dnsRules.Count -gt 0){$p=0;foreach($n in $dnsRules){if(Get-NetFirewallRule -Name ([string]$n) -ErrorAction SilentlyContinue){$p++}};Write-Host "Plain DNS block      : $p/$($dnsRules.Count) rule(s) present";if($p -ne $dnsRules.Count){$healthy=$false}}
}else{Write-Host 'System DNS           : DIRECT / unchanged by TorTunnel selected-app mode' -ForegroundColor Green;Write-Host 'Selected-app DNS     : uses Windows system resolver (not Tor-private)' -ForegroundColor Yellow}

$rules=@($state.EdgeKillSwitchRules);if($rules.Count -gt 0){$p=0;foreach($n in $rules){if(Get-NetFirewallRule -Name ([string]$n) -ErrorAction SilentlyContinue){$p++}};Write-Host "Edge kill-switch    : $p/$($rules.Count) rule(s) present";if($p -ne $rules.Count){$healthy=$false}}

$appPolicies=@();if($state.PSObject.Properties['AppBypassPolicies']){$appPolicies=@($state.AppBypassPolicies)}
$torPolicies=@();if($state.PSObject.Properties['TorAppPolicies']){$torPolicies=@($state.TorAppPolicies)}
if(($appPolicies.Count+$torPolicies.Count)-gt 0){$rp=Get-TTIPv4RoutePoliciesState;$ok=($rp -eq 'enabled');Write-Host "IPv4 routepolicies  : $rp" -ForegroundColor $(if($ok){'Green'}else{'Red'});if(-not $ok){$healthy=$false}}
foreach($entry in $appPolicies){$exists=$false;try{$exists=Test-TTAppRoutePolicy -PolicyKey ([string]$entry.PolicyKey)}catch{};Write-Host (("DIRECT $($entry.Name)").PadRight(20)+': '+$(if($exists){'ACTIVE'}else{'MISSING'})) -ForegroundColor $(if($exists){'Green'}else{'Red'});if(-not $exists){$healthy=$false}}
foreach($entry in $torPolicies){$exists=$false;try{$exists=Test-TTAppRoutePolicy -PolicyKey ([string]$entry.PolicyKey)}catch{};Write-Host (("TOR $($entry.Name)").PadRight(20)+': '+$(if($exists){'ACTIVE'}else{'MISSING'})) -ForegroundColor $(if($exists){'Green'}else{'Red'});if(-not $exists){$healthy=$false}}
if($mode -eq 'selectedappsonly'){$fr=@();if($state.PSObject.Properties['TorAppFirewallRules']){$fr=@($state.TorAppFirewallRules)};if($fr.Count -gt 0){$p=0;foreach($n in $fr){if(Get-NetFirewallRule -Name ([string]$n) -ErrorAction SilentlyContinue){$p++}};Write-Host "TOR app firewall    : $p/$($fr.Count) rule(s) present";if($p -ne $fr.Count){$healthy=$false}}}

try{$dnsProbe=Resolve-DnsName -Name 'example.com' -Type A -ErrorAction Stop;Write-Host 'DNS resolution       : WORKING' -ForegroundColor Green}catch{Write-Host "DNS resolution       : FAILED - $($_.Exception.Message)" -ForegroundColor Red;$healthy=$false}

# Passive IPv6 leak-risk screening: NEVER originate IPv6 traffic for a health check.
# A remote IPv6 test could reveal the physical IPv6 address if the tunnel fails.
# Adapter/route state is still not proof of absence of every possible leak.
if($mode -eq 'systemwide' -and $settings.DisableIPv6){
    $bindingsChecked=0;$bindingUnknown=$false;$enabledIPv6=New-Object 'System.Collections.Generic.List[string]'
    foreach($guidText in @($state.RelevantAdapterGuids)){
        try{
            $adapter=Find-TTAdapterByGuid -GuidText ([string]$guidText)
            if(-not $adapter){$bindingUnknown=$true;continue}
            $binding=@(Get-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop)
            if($binding.Count -lt 1){$bindingUnknown=$true;continue}
            $bindingsChecked++
            if(@($binding|Where-Object{$_.Enabled}).Count -gt 0){$enabledIPv6.Add([string]$adapter.Name)}
        }catch{$bindingUnknown=$true}
    }
    $v6Routes=@()
    try{$v6Routes=@(Get-NetRoute -AddressFamily IPv6 -ErrorAction Stop | Where-Object{$_.DestinationPrefix -eq '::/0'})}catch{$bindingUnknown=$true}
    if($bindingsChecked -gt 0 -and -not $bindingUnknown -and $enabledIPv6.Count -eq 0 -and $v6Routes.Count -eq 0){
        Write-Host 'IPv6 egress controls : ADAPTER IPv6 DISABLED / NO DEFAULT ROUTE (passive only)' -ForegroundColor Green
    }else{
        $description='Enabled bindings='+$enabledIPv6.Count+'; IPv6 default routes='+$v6Routes.Count+'; inspection uncertain='+$bindingUnknown
        Write-Host ('IPv6 egress controls : CHECK REQUIRED - '+$description) -ForegroundColor Red
        $healthy=$false
    }
}elseif($mode -eq 'systemwide'){
    Write-Host 'IPv6 egress controls : NOT VERIFIED (IPv6 blocking disabled)' -ForegroundColor Yellow
}else{Write-Host 'IPv6 egress controls : NOT VERIFIED (SelectedAppsOnly system routing direct)' -ForegroundColor Yellow}

$exitIP=$null;$torObj=$null
if($mode -eq 'systemwide'){$text=Invoke-TTCurlText @('--silent','--max-time','20','https://check.torproject.org/api/ip');if($text){try{$torObj=$text|ConvertFrom-Json}catch{}};if(-not $torObj -or -not $torObj.IsTor){Write-Host 'System IsTor         : False/FAILED' -ForegroundColor Red;$healthy=$false}else{$exitIP=[string]$torObj.IP;Write-Host 'System IsTor         : True' -ForegroundColor Green;Write-Host "Exit IP              : $exitIP"}}
else{$torObj=Get-TTTorCheckViaSocks -SocksPort $settings.SocksPort;if(-not $torObj){Write-Host 'Tor SOCKS IsTor      : FAILED' -ForegroundColor Red;$healthy=$false}else{$exitIP=[string]$torObj.IP;Write-Host 'Tor SOCKS IsTor      : True' -ForegroundColor Green;Write-Host "Tor exit IP          : $exitIP"};$direct=Invoke-TTCurlText @('--silent','--max-time','20','https://check.torproject.org/api/ip');if($direct){try{$d=$direct|ConvertFrom-Json;if($d.IsTor){Write-Host 'System default path  : TOR (unexpected)' -ForegroundColor Red;$healthy=$false}else{Write-Host 'System default path  : DIRECT' -ForegroundColor Green}}catch{Write-Host 'System default path  : DIRECT/unknown response' -ForegroundColor Yellow}}}

$country=$null;if($exitIP){try{$layout=Resolve-TTLayout -Root $Root;$country=Get-TTGeoIpCountry -IPAddress $exitIP -GeoIPFile $layout.GeoIP}catch{}}
if($country){Write-Host "Country              : $country (Tor local GeoIP)"}else{Write-Host 'Country              : unavailable (local GeoIP only; not a health failure)' -ForegroundColor Yellow}
Write-Host ''
if($healthy){Write-Host 'Overall              : HEALTHY' -ForegroundColor Green}else{Write-Host 'Overall              : ATTENTION NEEDED' -ForegroundColor Red}
if($PauseAtEnd){[void](Read-Host 'Press Enter to close')}
if(-not $healthy){exit 1}
