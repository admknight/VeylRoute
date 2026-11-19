# TorTunnel Universal Control Center v2 - portable component setup.
# No network configuration is changed by this file.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Inventory','DownloadHelpers','ImportFolder')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Root,
    [string]$SourceDirectory
)
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath($Root)
$helper=Join-Path $rootPath 'tun2socks'
$runtime=Join-Path $rootPath 'runtime\component-setup'
$utf8=New-Object System.Text.UTF8Encoding($false)
$wintunUrl='https://www.wintun.net/builds/wintun-0.14.1.zip'
$wintunSha='07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51'
$tunUrl='https://github.com/xjasonlyu/tun2socks/releases/download/v2.7.0/tun2socks-windows-amd64.zip'
$tunSha='c5d46e9452f6c9cc7c15ab9158d6d6a0169ceecd6bca019ce476b49337d2be43'
function Assert-Stopped {
    if(Test-Path -LiteralPath (Join-Path $rootPath 'runtime\session-state.json')){throw 'Stop or recover the current TorTunnel session before changing binaries.'}
    foreach($name in @('tor','tun2socks','lyrebird')) {
        $active=@(Get-Process -Name $name -ErrorAction SilentlyContinue)
        if($active.Count -gt 0){
            $pids=(@($active | ForEach-Object { [string]$_.Id }) -join ', ')
            throw "A $name process is running (PID: $pids). Stop the existing VeylRoute/TorTunnel connection from its controller before installing components. Binary replacement remains blocked."
        }
    }
}
function Get-File([string]$Target,[string]$Relative){return (Join-Path $Target $Relative)}
function Sha([string]$File){return (Get-FileHash -Algorithm SHA256 -LiteralPath $File).Hash.ToLowerInvariant()}
function Assert-Hash([string]$File,[string]$Expected){
    if((Sha $File) -ne $Expected.ToLowerInvariant()){throw "SHA256 mismatch: $([IO.Path]::GetFileName($File)). Nothing has been installed."}
}
function Extract-SingleFile([string]$Zip,[string]$Pattern,[string]$Destination){
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $matched=@($archive.Entries | Where-Object { $_.FullName.Replace('\','/') -match $Pattern -and $_.Length -gt 10240 })
        if($matched.Count -ne 1){throw "Expected one matching file in archive; got $($matched.Count)."}
        $entry=$matched[0]
        if($entry.FullName -match '(^|/)\.\.(/|$)' -or $entry.FullName.StartsWith('/')){throw 'Archive entry contains unsafe path.'}
        $parent=Split-Path -Parent $Destination
        if(-not(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force | Out-Null}
        $stream=$entry.Open()
        $destStream=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
        try{$stream.CopyTo($destStream)}finally{$destStream.Dispose();$stream.Dispose()}
    }finally{$archive.Dispose()}
}
function Ensure-PE([string]$File){
    $bytes=[IO.File]::ReadAllBytes($File)
    if($bytes.Length -lt 10240 -or $bytes[0] -ne 77 -or $bytes[1] -ne 90){throw "Unexpected Windows executable format: $File"}
}
function Commit-Helpers([string]$TunExe,[string]$WintunDll,[string]$Source){
    Assert-Stopped
    Ensure-PE $TunExe; Ensure-PE $WintunDll
    $targets=@(@{From=$TunExe;To=(Join-Path $helper 'tun2socks.exe')},@{From=$WintunDll;To=(Join-Path $helper 'wintun.dll')})
    $backup=Join-Path $runtime ('backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $helper -Force | Out-Null
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $changed=New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach($t in $targets){
            $name=[IO.Path]::GetFileName($t.To)
            if(Test-Path -LiteralPath $t.To){Copy-Item -LiteralPath $t.To -Destination (Join-Path $backup $name) -ErrorAction Stop}
            $changed.Add($t.To)
            Copy-Item -LiteralPath $t.From -Destination $t.To -Force -ErrorAction Stop
            if((Sha $t.From) -ne (Sha $t.To)){throw "Installed helper did not match staged binary: $name"}
        }
        $receipt=[ordered]@{installedAt=(Get-Date).ToString('o');source=$Source;rollbackFolder=$backup;
            tun2socksSha256=(Sha (Join-Path $helper 'tun2socks.exe'));wintunSha256=(Sha (Join-Path $helper 'wintun.dll'))}
        [IO.File]::WriteAllText((Join-Path $runtime 'helpers-install.json'),($receipt|ConvertTo-Json -Depth 5),$utf8)
        Write-Output 'Wintun and tun2socks helpers installed. Original helper files retained in backup.'
    }catch{
        $reason=$_.Exception.Message
        foreach($target in $changed){
            try{$b=Join-Path $backup ([IO.Path]::GetFileName($target));if(Test-Path -LiteralPath $b){Copy-Item -LiteralPath $b -Destination $target -Force -ErrorAction Stop}else{Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue}}catch{$reason+=' | rollback issue: '+$_.Exception.Message}
        }
        throw $reason
    }
}
function Find-SourceFile([string]$Folder,[string]$Name){
    if(-not(Test-Path -LiteralPath $Folder -PathType Container)){return $null}
    return (Get-ChildItem -LiteralPath $Folder -Recurse -File -Filter $Name -ErrorAction Stop | Select-Object -First 1 -ExpandProperty FullName)
}
function Inventory {
    $files=[ordered]@{
      'Tor'=(Find-SourceFile (Join-Path $rootPath 'Tor') 'tor.exe');
      'lyrebird'=(Find-SourceFile (Join-Path $rootPath 'Tor') 'lyrebird.exe');
      'GeoIP'=(Find-SourceFile (Join-Path $rootPath 'Tor') 'geoip');
      'GeoIP6'=(Find-SourceFile (Join-Path $rootPath 'Tor') 'geoip6');
      'tun2socks'=(Join-Path $helper 'tun2socks.exe');
      'Wintun'=(Join-Path $helper 'wintun.dll')
    }
    $complete=$true
    foreach($k in $files.Keys){
        $p=[string]$files[$k]
        if($p -and (Test-Path -LiteralPath $p -PathType Leaf)){
            Write-Output ("{0,-12}: PRESENT | {1} | SHA256 {2}" -f $k,$p,(Sha $p))
        }else{Write-Output ("{0,-12}: MISSING" -f $k);$complete=$false}
    }
    if(-not $complete){Write-Output 'Preflight will not connect until every required portable component exists.'}
}
if(-not(Test-Path -LiteralPath $runtime)){New-Item -ItemType Directory -Path $runtime -Force | Out-Null}
if($Action -eq 'Inventory'){Inventory;exit 0}
. (Join-Path $PSScriptRoot 'TorTunnel.TransferProgress.ps1')
# Start telemetry before guards: a blocked safety check must be reported, not hidden.
if($Action -eq 'DownloadHelpers'){
    Initialize-VeylProgress $rootPath 'ProvisionHelpers'
    $stage=''
    try{
        Write-VeylProgress 'Checking whether component replacement is safe' 'Running' 0 -1 $helper 'A running Tor or tun2socks process prevents binary replacement.'
        Assert-Stopped
        [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $stage=Join-Path $runtime ('download-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $wZip=Join-Path $stage 'wintun-0.14.1.zip'; $tZip=Join-Path $stage 'tun2socks-v2.7.0-amd64.zip'
        Write-Output 'Downloading Wintun from official source...'
        $null = Receive-VeylDownload $wintunUrl $wZip 'Wintun 0.14.1' @('www.wintun.net','wintun.net')
        Write-VeylProgress 'Checking Wintun SHA256' 'Running' 0 -1 $wZip 'Comparing with the published fixed archive checksum.'
        Assert-Hash $wZip $wintunSha
        Write-Output 'Wintun official SHA256: MATCH.'
        Write-Output 'Downloading tun2socks v2.7.0 Windows amd64...'
        $null = Receive-VeylDownload $tunUrl $tZip 'tun2socks 2.7.0' @('github.com','release-assets.githubusercontent.com','objects.githubusercontent.com','github-releases.githubusercontent.com')
        Write-VeylProgress 'Checking tun2socks SHA256' 'Running' 0 -1 $tZip 'Comparing with the published fixed release checksum.'
        Assert-Hash $tZip $tunSha
        Write-Output 'tun2socks release SHA256: MATCH.'
        $tExe=Join-Path $stage 'tun2socks.exe'; $wDll=Join-Path $stage 'wintun.dll'
        Write-VeylProgress 'Extracting signed Windows helpers' 'Running' 0 -1 $helper 'Extracting the checksum-matched archives to isolated staging.'
        Extract-SingleFile $tZip '(?i)(^|/)tun2socks(?:-windows-amd64)?\.exe$' $tExe
        Extract-SingleFile $wZip '(?i)(^|/)(amd64|x64)/wintun\.dll$' $wDll
        Ensure-PE $tExe;Ensure-PE $wDll
        Write-VeylProgress 'Verifying Wintun Authenticode signature' 'Running' 0 -1 $wDll 'A valid signed Wintun DLL is required.'
        $winSig=Get-AuthenticodeSignature -LiteralPath $wDll
        if($winSig.Status -ne 'Valid'){throw 'Wintun DLL Authenticode signature was not validated; refusing to install.'}
        Write-VeylProgress 'Installing and comparing helper binaries' 'Running' 0 -1 $helper 'Changes are backed up and verified against staging.'
        Commit-Helpers $tExe $wDll 'Wintun official checksum + signed DLL / tun2socks release SHA256'
        $installedTun=Join-Path $helper 'tun2socks.exe'; $installedWin=Join-Path $helper 'wintun.dll'
        if(-not (Test-Path -LiteralPath $installedTun -PathType Leaf) -or -not (Test-Path -LiteralPath $installedWin -PathType Leaf)){
            throw 'Helper installation returned but required files were not found at their destination.'
        }
        Write-VeylProgress 'Wintun and tun2socks installed' 'Completed' 0 -1 $helper ('Present at: '+$installedTun+' | '+$installedWin+'. Checksums and Wintun signature validated.')
    }catch{
        $cause=$_.Exception.Message
        try { Write-VeylProgress $script:VeylProgressStage 'Failed' 0 -1 $helper $cause }catch{}
        throw ("Wintun/tun2socks component setup failed during '$script:VeylProgressStage': $cause")
    }finally{
        if($stage -and (Test-Path -LiteralPath $stage)){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
    }
    exit 0
}
if($Action -eq 'ImportFolder'){
    Initialize-VeylProgress $rootPath 'ImportComponents'
    Write-VeylProgress 'Inspecting imported binaries' 'Running' 0 -1 $SourceDirectory 'Importing from a selected trusted local folder.'
    Assert-Stopped
    if(-not $SourceDirectory){throw 'Select a trusted folder containing Tor and/or tun2socks files.'}
    $src=[IO.Path]::GetFullPath($SourceDirectory)
    if(-not(Test-Path -LiteralPath $src -PathType Container)){throw 'Selected import folder not found.'}
    if($rootPath.StartsWith($src.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or $src.StartsWith($rootPath.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){
        throw 'Use a separate source folder for importing binaries (not the TorTunnel install folder).'
    }
    $stage=Join-Path $runtime ('import-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try{
        $imported=$false
        $tor=Find-SourceFile $src 'tor.exe';$pt=Find-SourceFile $src 'lyrebird.exe';$geo=Find-SourceFile $src 'geoip';$geo6=Find-SourceFile $src 'geoip6'
        if($tor -and $pt -and $geo -and $geo6){
            $newTor=Join-Path $stage 'Tor';$torParent=Split-Path -Parent $tor
            $newTorInner=Join-Path $newTor 'tor';$newData=Join-Path $newTor 'data'
            New-Item -ItemType Directory -Path $newTorInner -Force | Out-Null
            New-Item -ItemType Directory -Path $newData -Force | Out-Null
            # Copy parent for Tor dynamic libraries, pluggable transports and licenses.
            Copy-Item -Path (Join-Path $torParent '*') -Destination $newTorInner -Recurse -Force -ErrorAction Stop
            $ptDst=Join-Path $newTorInner 'pluggable_transports';New-Item -ItemType Directory -Path $ptDst -Force | Out-Null
            Copy-Item -LiteralPath $pt -Destination (Join-Path $ptDst 'lyrebird.exe') -Force
            Copy-Item -LiteralPath $geo -Destination (Join-Path $newData 'geoip') -Force
            Copy-Item -LiteralPath $geo6 -Destination (Join-Path $newData 'geoip6') -Force
            Ensure-PE (Join-Path $newTorInner 'tor.exe'); Ensure-PE (Join-Path $ptDst 'lyrebird.exe')
            $dest=Join-Path $rootPath 'Tor';$backup=Join-Path $rootPath ('Tor.import-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
            if(Test-Path -LiteralPath $dest){[IO.Directory]::Move($dest,$backup)}
            try{[IO.Directory]::Move($newTor,$dest)}catch{if(Test-Path -LiteralPath $backup){[IO.Directory]::Move($backup,$dest)};throw}
            Write-Output 'TOR: imported trusted user-supplied binaries. Authenticity not independently verified. Previous Tor directory retained if present.'
            $imported=$true
        }else{Write-Output 'Tor bundle not imported: tor.exe, lyrebird.exe and both geoip files must all be present.'}
        $tun=Find-SourceFile $src 'tun2socks.exe';$wintun=Find-SourceFile $src 'wintun.dll'
        if($tun -and $wintun){Commit-Helpers $tun $wintun 'User-selected folder; authenticity NOT independently verified';$imported=$true}
        else{Write-Output 'Helpers not imported: tun2socks.exe and wintun.dll must both be present.'}
        if(-not $imported){throw 'No complete Tor or helper binary set found in that folder.'}
        Write-VeylProgress 'Imported components placed in portable folders' 'Completed' 0 -1 $rootPath 'Check the component badges, then run Preflight to verify runtime compatibility.'
    }catch{
        try{Write-VeylProgress $script:VeylProgressStage 'Failed' 0 -1 $rootPath $_.Exception.Message}catch{}
        throw
    }finally{if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}}
    exit 0
}
