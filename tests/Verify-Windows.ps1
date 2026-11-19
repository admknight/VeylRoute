# VeylRoute Windows qualification tests. Read-only against the real installation.
# The worker dispatch tests run exclusively against a disposable TEMP fixture.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$passed = New-Object 'System.Collections.Generic.List[string]'
$failed = New-Object 'System.Collections.Generic.List[string]'
function Pass([string]$Name){$passed.Add($Name);Write-Host ('PASS  '+$Name) -ForegroundColor Green}
function Fail([string]$Name,[string]$Detail){$failed.Add($Name+': '+$Detail);Write-Host ('FAIL  '+$Name+' - '+$Detail) -ForegroundColor Red}
function Check([string]$Name,[scriptblock]$Block){
    try { & $Block; Pass $Name } catch { Fail $Name $_.Exception.Message }
}
Write-Host 'VeylRoute Windows qualification (no live network changes)' -ForegroundColor Cyan
Write-Host ('Location: '+$root)
Check 'Windows PowerShell 5.1 and 64-bit OS' {
    if ($PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitOperatingSystem) {
        throw 'Requires 64-bit Windows and Windows PowerShell 5.1.'
    }
}
Check 'Portable launcher and core scripts' {
    foreach($item in @('VeylRoute.vbs','ui\TorTunnel.ModernGui.ps1','ui\TorTunnel.ModernGui.xaml',
        '_internal\gui\TorTunnel.GuiWorker.ps1','_internal\gui\TorTunnel.PackageUpdater.ps1',
        '_internal\gui\TorTunnel.OpenPgpVerifier.ps1','_internal\Start-TorTunnel.ps1',
        '_internal\Stop-TorTunnel.ps1','_internal\Emergency-Reset-TorTunnel.ps1','_internal\NewCircuit-TorTunnel.ps1',
        '_internal\gui\TorTunnel.ExitAvailability.ps1','_internal\gui\TorTunnel.AppUpdate.ps1',
        'docs\APP-VERSION.txt','install-context.json')) {
        if(-not(Test-Path -LiteralPath (Join-Path $root $item) -PathType Leaf)) {throw ('Missing: '+$item)}
    }
}
Check 'Parse every PowerShell script using the native parser' {
    $all=@(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse -ErrorAction Stop)
    if($all.Count -lt 15){throw 'Unexpectedly few PowerShell scripts in package.'}
    foreach($file in $all){
        if($file.FullName -eq $PSCommandPath){continue}
        $tokens=$null;$parseErrors=$null
        $null=[System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
        if(@($parseErrors).Count -gt 0){
            throw ('Parse error in '+$file.Name+': '+($parseErrors[0].Message))
        }
    }
}
Check 'Parse and load the complete WPF layout' {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore -ErrorAction Stop
    Add-Type -AssemblyName WindowsBase -ErrorAction Stop
    $xamlPath=Join-Path $root 'ui\TorTunnel.ModernGui.xaml'
    $xml=[xml][IO.File]::ReadAllText($xamlPath)
    if(-not $xml.DocumentElement){throw 'XAML has no document root.'}
    $reader=[Xml.XmlReader]::Create($xamlPath)
    try{
        $window=[System.Windows.Markup.XamlReader]::Load($reader)
        if(-not ($window -is [System.Windows.Window])){throw 'XAML root did not instantiate a Window.'}
    }finally{$reader.Close()}
}
Check 'GUI control bindings match WPF named elements' {
    $guiText=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.ps1'))
    $xamlText=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.xaml'))
    $begin=$guiText.IndexOf('$names=@(')
    $end=$guiText.IndexOf('foreach ($suffix in @(', $begin)
    if($begin -lt 0 -or $end -le $begin){throw 'Unable to find GUI registration contract.'}
    $registered=$guiText.Substring($begin,$end-$begin)
    foreach($key in @('LblBtnStop','BtnNewCircuit','BtnPrivacyRecheck','BtnCheckExits','CountryAvailabilityNote','LogSeveritySummary',
            'PrivacyHeadline','PrivacyCheckedAt','PrivacyTorValue','PrivacyDnsValue','PrivacyLeakValue','PrivacyIpv6Value','PrivacyFirewallValue','PrivacyRemedy')){
        if(-not $registered.Contains("'"+$key+"'")){throw ('GUI code did not register: '+$key)}
        if(-not $xamlText.Contains('Name="'+$key+'"')){throw ('WPF layout does not define: '+$key)}
    }
}
Check 'About navigation, update buttons and installation context' {
    $gui=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.ps1'))
    $xaml=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.xaml'))
    foreach($key in @('BtnAbout','PageAbout','AboutInstallType','AboutAppVersion','AboutUpdateStatus','BtnAboutCheckUpdate','BtnAboutUpdateNow','BtnAboutGitHub','BtnAboutLicenses','BtnAboutFullUpdates')){
        if(-not $xaml.Contains('Name="'+$key+'"')){throw ('About UI does not define: '+$key)}
        if(-not $gui.Contains("'"+$key+"'")){throw ('About control is not registered: '+$key)}
    }
    if(-not $gui.Contains("Run-Action 'AppUpdateCheck'") -or -not $gui.Contains("Run-Action 'AppUpdatePrepare'")){throw 'About page is not connected to both worker actions.'}
    if($xaml -match 'Adam Knight|Adam Knight'){throw 'Private identity remains in public WPF GUI.'}
    $mode=Get-Content -LiteralPath (Join-Path $root 'install-context.json') -Raw | ConvertFrom-Json
    if([int]$mode.format -ne 1 -or [string]$mode.installMode -ne 'portable'){throw 'Portable payload lacks its explicit install marker.'}
}
Check 'Application update safeguards and edition-specific packaging' {
    $updater=[IO.File]::ReadAllText((Join-Path $root '_internal\gui\TorTunnel.AppUpdate.ps1'))
    $worker=[IO.File]::ReadAllText((Join-Path $root '_internal\gui\TorTunnel.GuiWorker.ps1'))
    foreach($required in @('SHA256SUMS.txt','Get-InstallMode','Get-ReleaseInfo','Assert-Sha','Assert-Idle','Apply-Portable','-Setup.exe','-Portable.zip','ParentPid','Get-ChildPath','backup-','app-update','[IO.Compression.ZipFile]::ExtractToDirectory')){
        if(-not $updater.Contains($required)){throw ('App update safeguard missing: '+$required)}
    }
    if(-not $updater.Contains('if($mode -eq '+[char]39+'setup'+[char]39+')')){throw 'No setup-specific updater path.'}
    if(-not $worker.Contains("'AppUpdatePrepare'") -or -not $worker.Contains("'AppUpdateCheck'")){throw 'Worker lacks app update dispatch.'}
    if($updater -match '(?im)\s+-SkipCertificateCheck'){throw 'App updater must not skip TLS certificate verification.'}
    foreach($rel in @('packaging\install-context-setup.json','packaging\install-context-portable.json')){
        $path=Join-Path $root $rel
        if(Test-Path -LiteralPath (Join-Path $root 'packaging') -PathType Container){
            if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('Missing mode marker: '+$rel)}
        }
    }
}
Check 'Application updater Probe is local and never touches Tor networking' {
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $dir=Join-Path ([IO.Path]::GetTempPath()) ('VeylRoute-ModeProbe-'+[guid]::NewGuid().ToString('N'))
    try{
        New-Item -ItemType Directory -Path (Join-Path $dir 'docs') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'docs\APP-VERSION.txt'),'3.0.1')
        [IO.File]::WriteAllText((Join-Path $dir 'install-context.json'),'{"format":1,"installMode":"portable"}')
        $up=Join-Path $root '_internal\gui\TorTunnel.AppUpdate.ps1'
        $out=& $exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $up -Action Probe -Root $dir 2>&1
        if($LASTEXITCODE -ne 0 -or ($out -join "`n") -notmatch 'INSTALL MODE: portable'){throw ('Portable mode probe failed: '+($out -join ' '))}
        [IO.File]::WriteAllText((Join-Path $dir 'unins000.dat'),'fixture')
        [IO.File]::WriteAllText((Join-Path $dir 'install-context.json'),'{"format":1,"installMode":"setup"}')
        $out=& $exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $up -Action Probe -Root $dir 2>&1
        if($LASTEXITCODE -ne 0 -or ($out -join "`n") -notmatch 'INSTALL MODE: setup'){throw ('Setup mode probe failed: '+($out -join ' '))}
    }finally{Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue}
}
Check 'Privacy dashboard binds live source fields' {
    $guiText=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.ps1'))
    $xamlText=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.xaml'))
    $statusText=[IO.File]::ReadAllText((Join-Path $root '_internal\Status-TorTunnel.ps1'))
    foreach($required in @('PrivacyTorValue','PrivacyDnsValue','PrivacyLeakValue','PrivacyIpv6Value','PrivacyFirewallValue','PrivacyRemedy','BtnPrivacyRecheck')){
        if(-not $xamlText.Contains('Name="'+$required+'"')){throw ('Missing privacy UI: '+$required)}
    }
    if(-not $guiText.Contains('Show-VeylPrivacyStatus') -or -not $guiText.Contains("'Status','Health'")){
        throw 'Privacy status is not connected to the existing Health/Status completion path.'
    }
    if(-not $statusText.Contains('IPv6 egress controls') -or -not $statusText.Contains('Get-NetAdapterBinding')){throw 'Passive IPv6 leak-risk screening is missing from read-only status.'}
    if($statusText.Contains('api64.ipify.org') -or $statusText.Contains("@('-6'")){throw 'Automatic IPv6 probes must not expose a physical IPv6 address to an external service.'}
    if(-not $guiText.Contains("'NOT PROVEN'") -or -not $guiText.Contains('external DNS-path')){
        throw 'Overview must not assert that a local DoH check proves no DNS leaks.'
    }
}
Check 'Worker output reader allows concurrent writes and bounded retry' {
    $source=[IO.File]::ReadAllText((Join-Path $root '_internal\gui\TorTunnel.GuiWorker.ps1'))
    if($source.Contains('[IO.File]::ReadAllText($rawOut)')){throw 'Exclusive worker stdout read regression.'}
    if(-not $source.Contains('Read-TTWorkerOutput -Path $rawOut') -or
       -not $source.Contains('[IO.FileShare]::ReadWrite') -or
       -not $source.Contains('Start-Sleep -Milliseconds 160')){
       throw 'Expected non-exclusive, bounded worker stdout reader is missing.'
    }
    $functions=$null;$errors=$null
    $ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root '_internal\gui\TorTunnel.GuiWorker.ps1'),[ref]$functions,[ref]$errors)
    if(@($errors).Count -gt 0){throw 'Worker source fails parsing.'}
    $functionAst=$ast.Find({param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Read-TTWorkerOutput'},$true)
    if(-not $functionAst){throw 'Worker shared-read function is missing.'}
    . ([scriptblock]::Create($functionAst.Extent.Text))
    $probe=Join-Path ([IO.Path]::GetTempPath()) ('VeylRoute-SharedOutput-'+[guid]::NewGuid().ToString('N')+'.log')
    $writer=$null
    try {
        $writer=[IO.FileStream]::new($probe,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
        $line=[Text.Encoding]::UTF8.GetBytes('START FAILED: simulated bootstrap timeout')
        $writer.Write($line,0,$line.Length);$writer.Flush()
        $read=Read-TTWorkerOutput -Path $probe -Attempts 1
        if($read -notmatch 'START FAILED: simulated bootstrap timeout'){throw 'The reader missed concurrent writer output.'}
    }finally{
        if($writer){$writer.Dispose()}
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
}
Check 'Manual NEWNYM control is loopback and SAFECOOKIE protected' {
    $source=[IO.File]::ReadAllText((Join-Path $root '_internal\NewCircuit-TorTunnel.ps1'))
    $common=[IO.File]::ReadAllText((Join-Path $root '_internal\TorTunnel.Common.ps1'))
    $gui=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.ps1'))
    $xaml=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.xaml'))
    foreach($token in @('ControlPort auto','ControlPortWriteToFile','CookieAuthentication 1','CookieAuthFile')){
        if(-not $common.Contains($token)){throw ('Missing protected Tor startup option: '+$token)}
    }
    foreach($token in @('SAFECOOKIE','AUTHCHALLENGE SAFECOOKIE','SIGNAL NEWNYM','server-to-controller hash','controller-to-server hash',
            'Get-NetTCPConnection','OwningProcess','Get-CimInstance','Get-TTTorCheckViaSocks','Tor may rate-limit')){
        if(-not $source.Contains($token)){throw ('New circuit source lacks: '+$token)}
    }
    if(-not $source.Contains('127.0.0.1') -or $source.Contains('AUTHENTICATE '+[char]34+'0'+[char]34)){
        throw 'Control listener cannot be unprotected or remotely reachable.'
    }
    if(-not $gui.Contains("Run-Action 'NewCircuit'") -or -not $xaml.Contains('Name="BtnNewCircuit"')){
        throw 'New Circuit GUI action is missing.'
    }
}
Check 'SAFECOOKIE HMAC fixture can be independently verified' {
    $source=[IO.File]::ReadAllText((Join-Path $root '_internal\NewCircuit-TorTunnel.ps1'))
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root '_internal\NewCircuit-TorTunnel.ps1'),[ref]$tokens,[ref]$errors)
    if(@($errors).Count){throw 'NEWNYM script fails parser.'}
    $functionAst=$ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Get-TTSafeCookieHmac'},$true)
    if(-not $functionAst){throw 'SAFECOOKIE HMAC helper absent.'}
    . ([scriptblock]::Create($functionAst.Extent.Text))
    $cookie=[byte[]](0..31);$client=[byte[]](32..63);$server=[byte[]](64..95)
    # Expected values independently generated using Python hmac/hashlib.
    $expected='B47642DF2D5ABB84F69E6D02D41BED6B44AEE33E69562528A82166FC98BC0B1E'
    $actual=[BitConverter]::ToString((Get-TTSafeCookieHmac 'Tor safe cookie authentication controller-to-server hash' $cookie $client $server)).Replace('-','')
    if($actual -ne $expected){throw 'SAFECOOKIE HMAC implementation failed independent vector.'}
}
Check 'Cooperative cancellation contract' {
    $gui=[IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.ps1'))
    $engine=[IO.File]::ReadAllText((Join-Path $root '_internal\Start-TorTunnel.ps1'))
    $worker=[IO.File]::ReadAllText((Join-Path $root '_internal\gui\TorTunnel.GuiWorker.ps1'))
    if(-not $gui.Contains('Request-VeylStartCancellation') -or -not $gui.Contains('start-cancel-')){throw 'GUI cancellation marker missing.'}
    if(-not $worker.Contains("-CancelFile") -or -not $engine.Contains('Assert-TTNotCancelled')){throw 'Engine cancellation path incomplete.'}
    if($gui -match '(?im)BusyProc\.Kill\('){throw 'Do not kill the live Start worker during routing changes.'}
}
Check 'Windows EXE and installer build source available' {
    foreach($rel in @('packaging\VeylRouteLauncher.cs','packaging\BUILD-WINDOWS.ps1','packaging\VeylRoute.iss')){
        if(-not (Test-Path -LiteralPath (Join-Path $root $rel) -PathType Leaf)){throw ('Missing Windows build source: '+$rel)}
    }
    $installer=[IO.File]::ReadAllText((Join-Path $root 'packaging\VeylRoute.iss'))
    if(-not $installer.Contains('uninsneveruninstall') -or -not $installer.Contains('InitializeUninstall') -or
       -not $installer.Contains('session-state.json')){throw 'Installer must protect config and block uninstall when a session exists.'}
}
Check 'WPF input event handlers avoid reserved automatic args' {
    $guiText = [IO.File]::ReadAllText((Join-Path $root 'ui\TorTunnel.ModernGui.ps1'))
    if ([regex]::IsMatch($guiText, '(?m)param\(\s*\$sender\s*,\s*\$args\s*\)')) {
        throw 'An input event handler binds the reserved PowerShell automatic $args variable.'
    }
    $wheel = '(?s)Add_PreviewMouseWheel\(\{\s*param\(\$sender,\[System\.Windows\.Input\.MouseWheelEventArgs\]\$wheelEventArgs\)\s*Route-TTNestedWheel\s+\$sender\s+\$wheelEventArgs\s*\}\)'
    if (-not [regex]::IsMatch($guiText, $wheel)) { throw 'MouseWheelEventArgs must reach Route-TTNestedWheel unchanged.' }
    $key = '(?s)TxtBridges\.Add_PreviewKeyDown\(\{\s*param\(\$sender,\[System\.Windows\.Input\.KeyEventArgs\]\$keyEventArgs\).*?\$keyEventArgs\.Handled\s*=\s*\$true'
    if (-not [regex]::IsMatch($guiText, $key)) { throw 'Bridge KeyEventArgs handler binding is missing or incorrect.' }
}
# Exercise worker parameter contracts without ever running actual Tor, Wintun,
# firewall, preflight, installation or recovery scripts.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('VeylRoute-Dispatch-'+[guid]::NewGuid().ToString('N'))
try {
    $int=Join-Path $fixture '_internal';$gui=Join-Path $int 'gui'
    [void](New-Item -ItemType Directory -Path $gui -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $fixture 'runtime\gui') -Force)
    $utf8=New-Object System.Text.UTF8Encoding($false)
    Copy-Item -LiteralPath (Join-Path $root '_internal\gui\TorTunnel.GuiWorker.ps1') -Destination $gui -Force
    $engineStub=@'
[CmdletBinding()]
param([string]$Root,[string]$RoutingMode,[switch]$NoPause,[switch]$Recovery,[string]$OutputPath,[string]$CancelFile)
Write-Output ('DISPATCH_OK engine Mode='+$RoutingMode+' Recovery='+$Recovery.IsPresent+' CancelFile='+$CancelFile)
'@
    $toolsStub=@'
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Action,[string]$Root,[string]$SourceDirectory,[string]$OutputPath)
Write-Output ('DISPATCH_OK Action='+$Action)
if($Action -eq 'Install') {[Console]::Error.WriteLine('SIMULATED_STDERR_FAILURE');exit 0}
'@
    foreach($name in @('Start-TorTunnel','Stop-TorTunnel','Check-TorTunnel','Status-TorTunnel','NewCircuit-TorTunnel')){
        [IO.File]::WriteAllText((Join-Path $int ($name+'.ps1')),$engineStub,$utf8)
    }
    foreach($name in @('TorTunnel.PackageUpdater','TorTunnel.BinarySetup','TorTunnel.Maintenance')){
        [IO.File]::WriteAllText((Join-Path $gui ($name+'.ps1')),$toolsStub,$utf8)
    }
    [IO.File]::WriteAllText((Join-Path $gui 'TorTunnel.VersionCheck.ps1'),$engineStub,$utf8)
    $availabilityStub=@'
[CmdletBinding()]
param([string]$Root)
$dir=Join-Path $Root 'runtime\gui'
$rec=[ordered]@{format=1;source='Tor Project Onionoo running relays with Exit flag';fetchedAtUtc=[datetime]::UtcNow.ToString('o');totalRunningExits=2;counts=@{us=2}}
[IO.File]::WriteAllText((Join-Path $dir 'exit-availability.json'),($rec|ConvertTo-Json -Depth 5))
Write-Output 'DISPATCH_OK ExitAvailability'
'@
    [IO.File]::WriteAllText((Join-Path $gui 'TorTunnel.ExitAvailability.ps1'),$availabilityStub,$utf8)
    $appUpdateStub=@'
[CmdletBinding()]
param([string]$Root,[string]$Action)
$now=[datetime]::UtcNow.ToString('o')
if($Action -eq 'Check'){
    $record=[ordered]@{format=1;checkedAtUtc=$now;status='UpToDate';mode='portable';tag='v3.0.1'}
    $path=Join-Path $Root 'runtime\gui\app-release.json'
    [IO.File]::WriteAllText($path,($record|ConvertTo-Json))
}elseif($Action -eq 'Prepare'){
    $folder=Join-Path $Root 'runtime\app-updates'
    [IO.Directory]::CreateDirectory($folder)|Out-Null
    $file=Join-Path $folder 'fixture.zip'
    [IO.File]::WriteAllText($file,'STUB')
    $sha=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $record=[ordered]@{format=1;verifiedAtUtc=$now;status='Verified';mode='portable';packagePath=$file;sha256=$sha}
    [IO.File]::WriteAllText((Join-Path $folder 'verified-app-update.json'),($record|ConvertTo-Json))
}
Write-Output ('DISPATCH_OK AppUpdate Action='+$Action)
'@
    [IO.File]::WriteAllText((Join-Path $gui 'TorTunnel.AppUpdate.ps1'),$appUpdateStub,$utf8)
    $newCircuitStub=@'
[CmdletBinding()]
param([string]$Root)
Write-Output 'CIRCUIT REQUEST : ACKNOWLEDGED'
Write-Output 'DISPATCH_OK engine'
'@
    [IO.File]::WriteAllText((Join-Path $int 'NewCircuit-TorTunnel.ps1'),$newCircuitStub,$utf8)
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $worker=Join-Path $gui 'TorTunnel.GuiWorker.ps1'
    $cases=@(
        @('Start','', 'DISPATCH_OK engine Mode=SelectedAppsOnly'),
        @('Stop','', 'DISPATCH_OK engine'),
        @('NewCircuit','', 'DISPATCH_OK engine'),
        @('Preflight','', 'DISPATCH_OK engine'),
        @('Status','', 'DISPATCH_OK engine'),
        @('Health','', 'DISPATCH_OK engine'),
        @('Recover','', 'DISPATCH_OK engine'),
        @('Updates','', 'DISPATCH_OK engine'),
        @('AppUpdateCheck','', 'DISPATCH_OK AppUpdate Action=Check'),
        @('AppUpdatePrepare','', 'DISPATCH_OK AppUpdate Action=Prepare'),
        @('ExitAvailability','', 'DISPATCH_OK ExitAvailability'),
        @('Inventory','', 'DISPATCH_OK Action=Inventory'),
        @('ProvisionHelpers','', 'DISPATCH_OK Action=DownloadHelpers'),
        @('ImportComponents', $fixture, 'DISPATCH_OK Action=ImportFolder'),
        @('UpdatePrepare','', 'DISPATCH_OK Action=Prepare'),
        @('UpdateInstall','', 'DISPATCH_OK Action=Install'),
        @('UpdateRollback','', 'DISPATCH_OK Action=Rollback'),
        @('Tidy','', 'DISPATCH_OK Action=Tidy'),
        @('Untidy','', 'DISPATCH_OK Action=Untidy')
    )
    Check 'Worker refuses false Start success' {
        $startStub=Join-Path $int 'Start-TorTunnel.ps1'
        $originalStub=[IO.File]::ReadAllText($startStub)
        try{
            [IO.File]::WriteAllText($startStub,"Write-Output 'START FAILED: simulated Tor bootstrap timeout'; exit 0",$utf8)
            $log=Join-Path $fixture 'runtime\gui\Start-Failure.log'
            $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -Action Start -Root "'+$fixture+'" -LogPath "'+$log+'" -RoutingMode SystemWide'
            $p=Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            $record=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $log) 'last-result.json') -Raw | ConvertFrom-Json -ErrorAction Stop
            $raw=Get-Content -LiteralPath $log -Raw
            if($p.ExitCode -ne 34 -or [int]$record.exitCode -ne 34){throw 'False Start success was not converted to nonzero 34.'}
            if($raw -notmatch 'START FAILED: simulated Tor bootstrap timeout'){throw 'Simulated failure details missing from activity.'}
        }finally{[IO.File]::WriteAllText($startStub,$originalStub,$utf8)}
    }
    Check 'Worker rejects missing circuit acknowledgement' {
        $target=Join-Path $int 'NewCircuit-TorTunnel.ps1'
        $original=[IO.File]::ReadAllText($target)
        try{
            [IO.File]::WriteAllText($target,"Write-Output 'No acknowledgement from the child'; exit 0",$utf8)
            $log=Join-Path $fixture 'runtime\gui\Circuit-Missing-Ack.log'
            $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -Action NewCircuit -Root "'+$fixture+'" -LogPath "'+$log+'"'
            $proc=Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            $record=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $log) 'last-result.json') -Raw | ConvertFrom-Json
            if([int]$proc.ExitCode -ne 36 -or [int]$record.exitCode -ne 36){throw 'Missing NEWNYM acknowledgement was incorrectly classified as success.'}
        }finally{[IO.File]::WriteAllText($target,$original,$utf8)}
    }
    foreach($case in $cases){
        $action=$case[0];$source=$case[1];$expected=$case[2]
        Check ('Worker dispatch: '+$action) {
            $log=Join-Path (Join-Path $fixture 'runtime\gui') ($action+'.log')
            $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -Action '+$action+' -Root "'+$fixture+'" -LogPath "'+$log+'" -RoutingMode SelectedAppsOnly'
            if($source){$arguments+=' -SourceDirectory "'+$source+'"'}
            $p=Start-Process -FilePath $exe -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            if(-not(Test-Path -LiteralPath $log)){throw 'Worker did not produce a log.'}
            $raw=Get-Content -LiteralPath $log -Raw
            if(-not $raw.Contains($expected)){throw ('Missing expected child marker (exit '+$p.ExitCode+').')}
            if($raw -match 'MissingMandatoryParameter|Unexpected token|ParserError'){throw 'PowerShell binding/parser failure.'}
            if($action -eq 'ExitAvailability'){
                $receipt=Join-Path $fixture 'runtime\gui\exit-availability.json'
                if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){throw 'Missing isolated exit snapshot.'}
                if([int]$p.ExitCode -ne 0){throw 'Fresh exit data receipt should pass the worker gate.'}
            }
            if($action -eq 'UpdateInstall'){
                # Result-file location is defined by the worker's -LogPath directory.
                # Keep this test aligned with the real GUI's runtime\gui log folder.
                $resultPath=Join-Path (Split-Path -Parent $log) 'last-result.json'
                if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){
                    throw 'Worker did not write its result beside the supplied -LogPath.'
                }
                $record=Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                if([string]$record.action -ne $action){throw 'Worker result has the wrong action.'}
                if([int]$record.exitCode -ne 35 -or [int]$p.ExitCode -ne 35){
                    throw 'Child stderr must produce the defined nonzero worker exit code 35.'
                }
                if([string]$record.detail -notmatch 'SIMULATED_STDERR_FAILURE'){
                    throw 'Worker result did not preserve the simulated child stderr diagnostic.'
                }
            }
        }
    }
}finally{
    try{if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop}}catch{Write-Warning ('Temp fixture cleanup: '+$_.Exception.Message)}
}
Write-Host ("`r`nPASSED: {0} | FAILED: {1}" -f $passed.Count,$failed.Count) -ForegroundColor Cyan
if($failed.Count -gt 0){Write-Host 'This build has NOT passed Windows qualification. Do not install new binaries until issues are corrected.' -ForegroundColor Yellow;exit 1}
Write-Host 'Static syntax, layout loading and isolated worker dispatch passed. Live Tor/DNS/WFP and binary installation remain separate tests.' -ForegroundColor Green
exit 0
