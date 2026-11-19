# VeylRoute application updater. Separate from Tor Expert Bundle provisioning.
# Windows PowerShell 5.1. Check -> Verify/download -> apply AFTER GUI exits.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Probe','Check','Prepare','Apply')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Root,
    [int]$ParentPid=0,
    [string]$Receipt=''
)
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath($Root)
$utf8=New-Object System.Text.UTF8Encoding($false)
$work=Join-Path $rootPath 'runtime\app-updates'
$gui=Join-Path $rootPath 'runtime\gui'
$checkPath=Join-Path $gui 'app-release.json'
$candidatePath=Join-Path $work 'verified-app-update.json'
$applyRecord=Join-Path $work 'last-apply.json'
$session=Join-Path $rootPath 'runtime\session-state.json'
$repo='admknight/VeylRoute'
$api='https://api.github.com/repos/'+$repo+'/releases/latest'
$script:Stage='Starting'
function Save-Record([string]$Path,$Data){
    $folder=[IO.Path]::GetDirectoryName($Path)
    if(-not(Test-Path -LiteralPath $folder -PathType Container)){[void](New-Item -ItemType Directory -Path $folder -Force)}
    $tmp=$Path+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $Data -Depth 10)+"`r`n",$utf8)
    try{if(Test-Path -LiteralPath $Path){Move-Item -LiteralPath $tmp -Destination $Path -Force}else{[IO.File]::Move($tmp,$Path)}}
    finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force}}
}
function Read-Record([string]$Path){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Missing record: $Path"};return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)}
function Get-InstallMode {
    $marker=Join-Path $rootPath 'install-context.json'
    if(Test-Path -LiteralPath $marker -PathType Leaf){
        $obj=Read-Record $marker
        if([int]$obj.format -ne 1 -or [string]$obj.installMode -notin @('portable','setup')){throw 'Invalid install-context.json; update mode is not trusted.'}
        if([string]$obj.installMode -eq 'setup' -and -not(Test-Path -LiteralPath (Join-Path $rootPath 'unins000.dat') -PathType Leaf)){
            throw 'Setup installation marker found but installer metadata is missing; repair the installation before updating.'
        }
        return [string]$obj.installMode
    }
    # Read-only compatibility for existing H5 installations without an explicit marker.
    if((Test-Path -LiteralPath (Join-Path $rootPath 'unins000.exe') -PathType Leaf) -and
       (Test-Path -LiteralPath (Join-Path $rootPath 'unins000.dat') -PathType Leaf)){return 'setup'}
    $programLocations=@([string]$env:ProgramFiles,[string]${env:ProgramFiles(x86)})
    foreach($location in $programLocations){
        if($location -and $rootPath.StartsWith(([IO.Path]::GetFullPath($location).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'Install type cannot be safely determined under Program Files. Repair using the Setup edition to restore the install marker.'
        }
    }
    return 'portable'
}
function Get-CurrentVersion {
    $file=Join-Path $rootPath 'docs\APP-VERSION.txt'
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw 'Application version marker is missing. Automatic application updates are unavailable.'}
    $v=[IO.File]::ReadAllText($file).Trim()
    if($v -notmatch '^\d+\.\d+\.\d+$'){throw 'Invalid local application version.'}
    return [version]$v
}
function Assert-Idle {
    if(Test-Path -LiteralPath $session -PathType Leaf){throw 'Disconnect or Recover VeylRoute first. An active or incomplete session-state file exists.'}
}
function Assert-ReleaseUrl([string]$Url,[string]$Tag,[string]$Name){
    if($Tag -notmatch '^v\d+\.\d+\.\d+$' -or $Name -notmatch '^[A-Za-z0-9._-]+$'){throw 'Invalid release asset identifier.'}
    $expected='https://github.com/'+$repo+'/releases/download/'+$Tag+'/'+$Name
    if($Url -cne $expected){throw ('Unexpected GitHub release asset URL for '+$Name)}
}
function Get-ReleaseInfo {
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers=@{'User-Agent'='VeylRoute-Windows-AppUpdater/3.0.1';'Accept'='application/vnd.github+json'}
    $release=Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 25 -UseBasicParsing -ErrorAction Stop
    if([bool]$release.draft -or [bool]$release.prerelease){throw 'GitHub did not provide a stable release.'}
    $tag=[string]$release.tag_name
    if($tag -notmatch '^v(\d+\.\d+\.\d+)$'){throw 'GitHub latest release has no supported stable semantic version tag.'}
    $v=[version]$Matches[1]
    $mode=Get-InstallMode
    $suffix=if($mode -eq 'setup'){'-Setup.exe'}else{'-Portable.zip'}
    # PowerShell -match cannot concatenate a RHS expression without parentheses.
    $matches=@($release.assets | Where-Object {$_.name -match ('^VeylRoute-Windows-[A-Za-z0-9._-]+' + [regex]::Escape($suffix) + '$')})
    $hashItems=@($release.assets | Where-Object {$_.name -ceq 'SHA256SUMS.txt'})
    if($matches.Count -ne 1 -or $hashItems.Count -ne 1){throw "The stable release does not provide exactly one $mode package and one checksum file."}
    $asset=$matches[0];$hashAsset=$hashItems[0]
    Assert-ReleaseUrl ([string]$asset.browser_download_url) $tag ([string]$asset.name)
    Assert-ReleaseUrl ([string]$hashAsset.browser_download_url) $tag 'SHA256SUMS.txt'
    if([double]$asset.size -le 1000 -or [double]$asset.size -gt 120MB){throw 'Release package has an unexpected download size.'}
    return [pscustomobject]@{tag=$tag;version=$v.ToString(3);mode=$mode;assetName=[string]$asset.name;assetUrl=[string]$asset.browser_download_url;assetDigest=[string]$asset.digest;checksumUrl=[string]$hashAsset.browser_download_url;checksumDigest=[string]$hashAsset.digest;size=[long]$asset.size}
}
function Get-VerifiedHashes([string]$Text,[string]$Name){
    $lines=@($Text -split '\r?\n' | Where-Object {$_ -match '\S'})
    $matches=@($lines | Where-Object {$_ -match ('(?i)^[a-f0-9]{64}\s+\*?'+[regex]::Escape($Name)+'$')})
    if($matches.Count -ne 1){throw 'Checksum manifest has no unambiguous SHA-256 entry for this package.'}
    $h=([regex]::Match($matches[0],'(?i)^[a-f0-9]{64}')).Value.ToLowerInvariant()
    return $h
}
function Invoke-Download([string]$Url,[string]$Destination){
    if((Test-Path -LiteralPath $Destination -PathType Leaf)){Remove-Item -LiteralPath $Destination -Force}
    $headers=@{'User-Agent'='VeylRoute-Windows-AppUpdater/3.0.1'}
    Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers $headers -TimeoutSec 90 -OutFile $Destination -ErrorAction Stop | Out-Null
    if(-not(Test-Path -LiteralPath $Destination -PathType Leaf)){throw 'Download did not create the expected file.'}
}
function Assert-Sha([string]$Path,[string]$Expected){
    if($Expected -notmatch '^[a-fA-F0-9]{64}$'){throw 'Expected SHA-256 digest is invalid.'}
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if($actual -cne $Expected.ToLowerInvariant()){throw "SHA-256 mismatch for $([IO.Path]::GetFileName($Path)). Nothing was installed."}
}
function Get-ChildPath([string]$Dir,[string]$Rel){
    $full=[IO.Path]::GetFullPath((Join-Path $Dir ($Rel.Replace('/','\'))))
    if(-not $full.StartsWith(($Dir.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Archive path escapes the application directory.'}
    return $full
}
function Apply-Portable([string]$Archive,[string]$Tag){
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $extract=Join-Path $work ('extract-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -Path $extract -ItemType Directory -Force)
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    $names=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $total=[long]0;$oneRoot='';$files=New-Object 'System.Collections.Generic.List[string]'
    try{
        foreach($entry in $zip.Entries){
            $name=$entry.FullName.Replace('\','/')
            if($name.StartsWith('/') -or $name.Contains(':') -or $name.Contains('//') -or $name.Split('/') -contains '..' -or $name.Split('/') -contains '.'){
                throw 'Unsafe path in the portable package.'
            }
            $segments=$name.TrimEnd('/').Split('/')
            if($segments.Count -lt 2){throw 'Portable package must have one top-level application directory.'}
            if(-not $oneRoot){$oneRoot=$segments[0]}
            if($segments[0] -cne $oneRoot){throw 'Portable package has multiple top-level directories.'}
            if($name.EndsWith('/')){continue}
            $rel=($segments | Select-Object -Skip 1) -join '/'
            if(-not $names.Add($rel)){throw 'Duplicate path in the portable package.'}
            $total+=[long]$entry.Length
            if($entry.Length -gt 35MB -or $total -gt 220MB){throw 'Unexpected archive extraction size.'}
            $files.Add($rel)
        }
    }finally{$zip.Dispose()}
    foreach($must in @('VeylRoute.exe','LICENSE','ui/TorTunnel.ModernGui.ps1','ui/TorTunnel.ModernGui.xaml','_internal/gui/TorTunnel.AppUpdate.ps1','docs/APP-VERSION.txt')){
        if(-not $names.Contains($must)){throw "Portable update archive lacks $must"}
    }
    [IO.Compression.ZipFile]::ExtractToDirectory($Archive,$extract)
    $payload=Join-Path $extract $oneRoot
    $newVersion=[IO.File]::ReadAllText((Get-ChildPath $payload 'docs/APP-VERSION.txt')).Trim()
    if($newVersion -cne $Tag.Substring(1)){throw 'The package application version does not match the stable release tag.'}
    $allowed=@('VeylRoute.exe','VeylRoute.vbs','START-HERE.cmd','VERSION.txt','README-FIRST.txt','LICENSE')
    $updateFiles=New-Object 'System.Collections.Generic.List[string]'
    foreach($file in $files){
        if($file -in $allowed -or $file.StartsWith('_internal/') -or $file.StartsWith('ui/') -or $file.StartsWith('docs/') -or $file.StartsWith('tests/')){$updateFiles.Add($file)}
    }
    $backup=Join-Path $work ('backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -Path $backup -ItemType Directory -Force)
    $touched=New-Object 'System.Collections.Generic.List[object]'
    # Two-phase local operation: first back up ALL affected originals, then copy.
    foreach($rel in $updateFiles){
        $destination=Get-ChildPath $rootPath $rel
        $exists=Test-Path -LiteralPath $destination -PathType Leaf
        if($exists){
            $save=Get-ChildPath $backup $rel
            [IO.Directory]::CreateDirectory(([IO.Path]::GetDirectoryName($save))) | Out-Null
            [IO.File]::Copy($destination,$save,$true)
        }
        $touched.Add([pscustomobject]@{rel=$rel;existed=[bool]$exists})
    }
    $copied=New-Object 'System.Collections.Generic.List[object]'
    Assert-Idle
    try {
        foreach($entry in $touched){
            $dest=Get-ChildPath $rootPath ([string]$entry.rel)
            $src=Get-ChildPath $payload ([string]$entry.rel)
            [IO.Directory]::CreateDirectory(([IO.Path]::GetDirectoryName($dest))) | Out-Null
            # Register BEFORE copying: even a partial overwrite must be rolled back.
            $copied.Add($entry)
            [IO.File]::Copy($src,$dest,$true)
        }
        $writtenVersion=[IO.File]::ReadAllText((Get-ChildPath $rootPath 'docs/APP-VERSION.txt')).Trim()
        if($writtenVersion -cne $newVersion){throw 'Post-copy version verification failed.'}
    }catch{
        $failure=$_.Exception.Message
        $rollbackErrors=New-Object 'System.Collections.Generic.List[string]'
        for($i=$copied.Count-1;$i -ge 0;$i--){
            $entry=$copied[$i]
            try{
                $dest=Get-ChildPath $rootPath ([string]$entry.rel)
                if($entry.existed){[IO.File]::Copy((Get-ChildPath $backup ([string]$entry.rel)),$dest,$true)}
                elseif(Test-Path -LiteralPath $dest){Remove-Item -LiteralPath $dest -Force}
            }catch{$rollbackErrors.Add([string]$entry.rel+': '+$_.Exception.Message)}
        }
        if($rollbackErrors.Count){throw ('Update failed: '+$failure+'; rollback incomplete: '+($rollbackErrors -join '; '))}
        throw ('Update failed and previous files restored: '+$failure)
    }
    Write-Output ('Portable application files replaced; config, Tor, tun2socks and runtime were preserved. Backup: '+$backup)
}
function Show-ApplyError([string]$Message){
    try{Add-Type -AssemblyName PresentationFramework;[void][System.Windows.MessageBox]::Show($Message,'VeylRoute update',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)}catch{}
}
try{
    if(-not(Test-Path -LiteralPath $rootPath -PathType Container)){throw 'VeylRoute folder not found.'}
    $mode=Get-InstallMode
    switch($Action){
        'Probe' {
            Write-Output ('INSTALL MODE: '+$mode)
            Write-Output ('APP VERSION: '+(Get-CurrentVersion).ToString(3))
        }
        'Check' {
            $local=Get-CurrentVersion
            $release=Get-ReleaseInfo
            $remote=[version]$release.version
            $status=if($remote -gt $local){'UpdateAvailable'}elseif($remote -eq $local){'UpToDate'}else{'LocalNewer'}
            $record=[ordered]@{format=1;checkedAtUtc=[datetime]::UtcNow.ToString('o');status=$status;mode=$mode;currentVersion=$local.ToString(3);latestVersion=$release.version;tag=$release.tag;assetName=$release.assetName;assetUrl=$release.assetUrl;assetDigest=$release.assetDigest;checksumUrl=$release.checksumUrl;checksumDigest=$release.checksumDigest;size=$release.size}
            Save-Record $checkPath $record
            Write-Output ('APP UPDATE CHECK: '+$status)
            Write-Output ('Installed app: '+$local+' | Latest stable: '+$remote+' | Edition: '+$mode)
        }
        'Prepare' {
            Assert-Idle
            $prior=Read-Record $checkPath
            if([int]$prior.format -ne 1 -or [string]$prior.status -ne 'UpdateAvailable' -or [string]$prior.mode -ne $mode){throw 'Check for application updates first; the result must be newer than the installed edition.'}
            if(([datetime]::Parse([string]$prior.checkedAtUtc)).ToUniversalTime() -lt [datetime]::UtcNow.AddHours(-3)){throw 'The update check expired; check again.'}
            $release=Get-ReleaseInfo
            if([string]$prior.tag -cne $release.tag -or [string]$prior.assetName -cne $release.assetName){throw 'The stable release changed; check for updates again.'}
            if([version]$release.version -le (Get-CurrentVersion)){throw 'No newer stable application version is available.'}
            [IO.Directory]::CreateDirectory($work) | Out-Null
            $target=Join-Path $work ('stage-'+$release.tag+'-'+[guid]::NewGuid().ToString('N'))
            [void](New-Item -Path $target -ItemType Directory)
            $package=Join-Path $target $release.assetName
            $checksum=Join-Path $target 'SHA256SUMS.txt'
            Invoke-Download $release.checksumUrl $checksum
            if($release.checksumDigest -match '^sha256:([a-fA-F0-9]{64})$'){Assert-Sha $checksum $Matches[1]}
            $expected=Get-VerifiedHashes ([IO.File]::ReadAllText($checksum)) $release.assetName
            if($release.assetDigest -match '^sha256:([a-fA-F0-9]{64})$' -and $expected -cne $Matches[1].ToLowerInvariant()){throw 'GitHub asset SHA-256 and published checksum file disagree.'}
            Invoke-Download $release.assetUrl $package
            Assert-Sha $package $expected
            if(([IO.FileInfo]$package).Length -ne $release.size){throw 'The downloaded file size differs from GitHub release metadata.'}
            Assert-Idle
            $record=[ordered]@{format=1;status='Verified';verifiedAtUtc=[datetime]::UtcNow.ToString('o');root=$rootPath;mode=$mode;version=$release.version;tag=$release.tag;packagePath=$package;assetName=$release.assetName;sha256=$expected;size=$release.size}
            Save-Record $candidatePath $record
            Write-Output ('APP UPDATE VERIFIED: '+$mode+' '+$release.tag)
            Write-Output ('SHA256: '+$expected)
            Write-Output 'No application or Tor files have been replaced.'
        }
        'Apply' {
            if($ParentPid -le 0){throw 'Application update needs the launching GUI process ID.'}
            if(-not $Receipt){$Receipt=$candidatePath}
            $record=Read-Record $Receipt
            if([int]$record.format -ne 1 -or [string]$record.status -ne 'Verified' -or [string]$record.mode -ne $mode -or [string]$record.root -cne $rootPath){throw 'The verified update receipt is missing or does not match this installation.'}
            if([string]$record.tag -notmatch '^v\d+\.\d+\.\d+$' -or [string]$record.version -cne [string]$record.tag.Substring(1)){throw 'Invalid update release version receipt.'}
            if([version][string]$record.version -le (Get-CurrentVersion)){throw 'The verified update is not newer than the installed application.'}
            $package=[IO.Path]::GetFullPath([string]$record.packagePath)
            if(-not $package.StartsWith(($work.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Prepared package is outside the application-update staging folder.'}
            if(-not(Test-Path -LiteralPath $package -PathType Leaf)){throw 'Verified application package is missing.'}
            Assert-Sha $package ([string]$record.sha256)
            if($ParentPid -eq $PID){throw 'Updater must run in a separate process.'}
            $parent=Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
            if($parent){if(-not $parent.WaitForExit(60000)){throw 'VeylRoute GUI did not exit; no files were replaced.'}}
            Assert-Idle
            # Recheck after waiting for GUI exit; do not apply to a newly active session.
            Assert-Sha $package ([string]$record.sha256)
            if($mode -eq 'setup'){
                if(-not $package.EndsWith('-Setup.exe',[StringComparison]::OrdinalIgnoreCase)){throw 'Setup installation requires the verified Setup EXE.'}
                $proc=Start-Process -FilePath $package -Wait -PassThru
                try{if([int]$proc.ExitCode -ne 0){throw ('Installer exited with code '+$proc.ExitCode)}}finally{$proc.Dispose()}
                if((Get-CurrentVersion).ToString(3) -cne [string]$record.version){throw 'Installer finished but expected application version was not observed.'}
            }else{
                if(-not $package.EndsWith('-Portable.zip',[StringComparison]::OrdinalIgnoreCase)){throw 'Portable installation requires the verified portable ZIP.'}
                Apply-Portable $package ([string]$record.tag)
            }
            Save-Record $applyRecord ([ordered]@{format=1;status='Completed';mode=$mode;installedVersion=[string]$record.version;checkedAtUtc=[datetime]::UtcNow.ToString('o')})
            Write-Output ('APP UPDATE INSTALLED: '+[string]$record.version+' ('+$mode+')')
            $launcher=Join-Path $rootPath 'VeylRoute.exe'
            if(Test-Path -LiteralPath $launcher -PathType Leaf){Start-Process -FilePath $launcher -WorkingDirectory $rootPath | Out-Null}
        }
    }
    exit 0
}catch{
    $detail=$_.Exception.Message
    try{if($Action -eq 'Apply'){Save-Record $applyRecord ([ordered]@{format=1;status='Failed';detail=$detail;checkedAtUtc=[datetime]::UtcNow.ToString('o')})}}catch{}
    Write-Error ('VeylRoute app update failed: '+$detail)
    if($Action -eq 'Apply'){Show-ApplyError ('VeylRoute could not complete the update. '+$detail+'`r`nNo networking changes were requested by the updater. If rollback was incomplete, restore from the app-updates backup folder.')}
    exit 1
}
