# TorTunnel Universal v2.1 Preview: signed Windows Expert Bundle installer for engine v3.5.1.
# Only this updater may change Tor binaries; tunnel engine/networking remains untouched.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Prepare','Install','Rollback')][string]$Action,
    [Parameter(Mandatory=$true)][string]$Root,
    [string]$SourceDirectory=''
)
$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($Root)
$torDir = Join-Path $rootPath 'Tor'
$workDir = Join-Path $rootPath 'runtime\component-updates'
$marker = Join-Path $workDir 'verified-expert-bundle.json'
$installMarker = Join-Path $workDir 'installed-expert-bundle.json'
$prepareRecord = Join-Path $workDir 'last-prepare-result.json'
$script:PrepareStage = 'Starting'
$trustedFingerprint = 'EF6E286DDA85EA2A4BA7DE684E2C6E8793298290'
$distIndex = 'https://dist.torproject.org/torbrowser/'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Save-Json([string]$Path,$Data) {
    $text = ($Data | ConvertTo-Json -Depth 8) + "`r`n"
    $tmp = $Path+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($tmp,$text,$utf8)
    if (Test-Path -LiteralPath $Path) { Move-Item -LiteralPath $tmp -Destination $Path -Force }
    else { [IO.File]::Move($tmp,$Path) }
}
# User-readable preparation stage. A failure never creates a verified install candidate.
function Set-PrepareStage([string]$Stage,[string]$Status,[string]$Detail='') {
    $script:PrepareStage=$Stage
    $record=[ordered]@{format=1;action='Prepare';stage=$Stage;status=$Status;detail=$Detail;checkedAt=(Get-Date).ToString('o')}
    Save-Json $prepareRecord $record
    $progressStatus=if($Status -eq 'Succeeded'){'Completed'}else{$Status}
    Write-VeylProgress $Stage $progressStatus 0 -1 '' $Detail
}
function Read-Json([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing update record: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
}
function Assert-Offline {
    if (Test-Path -LiteralPath (Join-Path $rootPath 'runtime\session-state.json')) {
        throw 'TorTunnel session-state exists. Disconnect using Stop or Recover before changing Tor binaries.'
    }
    foreach ($name in @('tor','tun2socks','lyrebird')) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) {
            throw "A $name process is running. Stop the tunnel before updating binaries."
        }
    }
}
function Assert-Signature([string]$Package,[string]$Signature,[string]$PublicKey) {
    $verifier=Join-Path $PSScriptRoot 'TorTunnel.OpenPgpVerifier.ps1'
    if(-not(Test-Path -LiteralPath $verifier -PathType Leaf)){throw 'Bundled OpenPGP verifier script is missing.'}
    # The verifier checks the Tor developers fingerprint, signing-subkey binding and detached signature.
    # A managed .NET library is acquired automatically inside TorTunnel on first use.
    & $verifier -Root $rootPath -Package $Package -Signature $Signature -PublicKey $PublicKey
    if(-not $?){throw 'In-app OpenPGP signature verification failed.'}
}
function Get-Version([string]$Exe) {
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Missing Tor executable: $Exe" }
    $p = New-Object Diagnostics.Process
    $p.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $p.StartInfo.FileName = $Exe
    $p.StartInfo.Arguments = '--version'
    $p.StartInfo.WorkingDirectory = [IO.Path]::GetDirectoryName($Exe)
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.CreateNoWindow = $true
    try {
        if (-not $p.Start()) { throw 'Unable to launch Tor for version verification.' }
        if (-not $p.WaitForExit(12000)) { try {$p.Kill()}catch{}; throw 'Tor version probe timed out.' }
        $text = $p.StandardOutput.ReadToEnd() + ' ' + $p.StandardError.ReadToEnd()
        if ($p.ExitCode -ne 0 -or $text -notmatch '(?i)\bTor(?:\s+version)?\s+v?(\d+\.\d+\.\d+\.\d+)\b') {
            throw 'Tor version probe did not return a successful known version.'
        }
        return $Matches[1]
    } finally { $p.Dispose() }
}
function Verify-PackageRecord {
    $data = Read-Json $marker
    if ([string]$data.signatureFingerprint -ne $trustedFingerprint -or [string]$data.status -ne 'Verified') { throw 'Update record is not marked verified with the trusted fingerprint.' }
    $pkg = [IO.Path]::GetFullPath([string]$data.package)
    $sig = [IO.Path]::GetFullPath([string]$data.signature)
    $publicKey = [IO.Path]::GetFullPath([string]$data.publicKey)
    if (-not $pkg.StartsWith($workDir.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or
        -not $sig.StartsWith($workDir.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) {
        throw 'An update record points outside the managed update folder.'
    }
    if (-not (Test-Path -LiteralPath $pkg -PathType Leaf) -or -not (Test-Path -LiteralPath $sig -PathType Leaf) -or -not (Test-Path -LiteralPath $publicKey -PathType Leaf)) { throw 'Verified archive/signature/signing key is missing.' }
    if(-not $publicKey.StartsWith($workDir.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Signing key path is outside the managed update folder.'}
    if((Get-FileHash -LiteralPath $publicKey -Algorithm SHA256).Hash -ne [string]$data.publicKeySha256){throw 'Tor signing key file changed since preparation.'}
    if ((Get-FileHash -LiteralPath $pkg -Algorithm SHA256).Hash -ne [string]$data.sha256) { throw 'Verified archive hash changed.' }
    Assert-Signature $pkg $sig $publicKey
    return $data
}
function Assert-SafeEntries([string]$Package) {
    $tar = Get-Command 'tar.exe' -ErrorAction SilentlyContinue
    if (-not $tar) { throw 'Windows tar.exe is required to inspect the Expert Bundle archive.' }
    $names = @(& $tar.Source -tzf $Package 2>&1)
    if ($LASTEXITCODE -ne 0 -or $names.Count -lt 4) { throw 'Unable to list signed archive contents.' }
    # Separate archive safety from the installed-file whitelist. Official signed
    # Expert Bundles also contain documentation (for example docs/), which is
    # harmless but is NOT part of the tor/data executable payload we promote.
    # Never permit absolute paths, parent traversal or Windows-special names.
    foreach ($raw in $names) {
        $item = [string]$raw
        if ($item -eq './') { continue } # harmless root directory entry
        if ($item.StartsWith('./')) { $item = $item.Substring(2) }
        if ([string]::IsNullOrWhiteSpace($item) -or $item.StartsWith('/') -or
            $item.Contains('\') -or $item -match '[\x00-\x1f:*?"<>|]') {
            throw "Unsafe path in signed bundle. Refusing extraction: $raw"
        }
        $relative = $item.TrimEnd('/')
        if (-not $relative) { throw "Empty path in signed bundle: $raw" }
        foreach ($segment in ($relative -split '/')) {
            if (-not $segment -or $segment -eq '.' -or $segment -eq '..' -or
                $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
                $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') {
                throw "Unsafe path segment in signed bundle. Refusing extraction: $raw"
            }
        }
    }
    # A safe-looking name can still be a symlink/hardlink/device node. Only
    # normal files and directories are accepted, including in ignored docs.
    $details = @(& $tar.Source -tvzf $Package 2>&1)
    if ($LASTEXITCODE -ne 0 -or $details.Count -ne $names.Count) {
        throw 'Unable to inspect signed archive entry types safely.'
    }
    foreach ($detail in $details) {
        $description = [string]$detail
        if ($description.Length -lt 1 -or ($description[0] -ne '-' -and $description[0] -ne 'd')) {
            throw 'Signed archive contains a link, special entry, or unrecognized tar type. Refusing extraction.'
        }
    }
    return [string]$tar.Source
}
# Discover only stable numeric release directories on the official Tor distribution host.
# The newest directory may contain Android builds only, so require Windows archive + signature.
function Get-OfficialWindowsBundle {
    $index=Invoke-WebRequest -Uri $distIndex -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
    if([int]$index.StatusCode -ne 200 -or ([uri]$index.BaseResponse.ResponseUri).Host -ne 'dist.torproject.org'){
        throw 'Official Tor distribution directory did not return a trusted HTTPS listing.'
    }
    $matches=@([regex]::Matches([string]$index.Content,'(?i)href\s*=\s*["\x27](?<release>\d+\.\d+(?:\.\d+)?)/["\x27]'))
    $versions=@($matches | ForEach-Object {$_.Groups['release'].Value} | Sort-Object -Unique | Sort-Object -Property {[version]$_} -Descending)
    if($versions.Count -lt 1){throw 'No stable Tor release directories found on the official distribution host.'}
    foreach($release in ($versions | Select-Object -First 12)){
        $listingUrl=$distIndex+$release+'/'
        try {
            $listing=Invoke-WebRequest -Uri $listingUrl -UseBasicParsing -TimeoutSec 25 -ErrorAction Stop
            if([int]$listing.StatusCode -ne 200 -or ([uri]$listing.BaseResponse.ResponseUri).Host -ne 'dist.torproject.org'){continue}
            $name='tor-expert-bundle-windows-x86_64-'+$release+'.tar.gz'
            $linkPattern='(?i)href\s*=\s*["\x27]'+[regex]::Escape($name)+'["\x27]'
            $sigPattern='(?i)href\s*=\s*["\x27]'+[regex]::Escape($name+'.asc')+'["\x27]'
            if([regex]::IsMatch([string]$listing.Content,$linkPattern) -and [regex]::IsMatch([string]$listing.Content,$sigPattern)){
                return [pscustomobject]@{Version=$release;Url=($listingUrl+$name)}
            }
        } catch {
            Write-Output ('Could not inspect release '+$release+': '+$_.Exception.Message)
        }
    }
    throw 'The official distribution host is reachable but no stable signed Windows x64 Expert Bundle was found. Import a signed archive and signature instead.'
}
function Copy-SignedImport([string]$Folder) {
    if(-not(Test-Path -LiteralPath $Folder -PathType Container)){throw 'Selected signed-bundle import folder does not exist.'}
    $candidates=@(Get-ChildItem -LiteralPath $Folder -File -ErrorAction Stop | Where-Object {
        $_.Name -match '^tor-expert-bundle-windows-x86_64-(\d+\.\d+(?:\.\d+)?)\.tar\.gz$'
    })
    if($candidates.Count -ne 1){throw 'Import folder must contain exactly one Windows x64 tor-expert-bundle-*.tar.gz file.'}
    $file=$candidates[0];$matched=[regex]::Match($file.Name,'^tor-expert-bundle-windows-x86_64-(?<v>\d+\.\d+(?:\.\d+)?)\.tar\.gz$')
    $v=$matched.Groups['v'].Value
    $sigSource=$file.FullName+'.asc'
    if(-not(Test-Path -LiteralPath $sigSource -PathType Leaf)){throw 'Detached signature is missing. Put the matching .tar.gz.asc beside the archive.'}
    $keySource=$null
    foreach($candidateName in @('tor-signing-key.asc','torbrowser-developers-public.asc','tor-developers-public.asc')){
        $candidate=Join-Path $Folder $candidateName
        if(Test-Path -LiteralPath $candidate -PathType Leaf){$keySource=$candidate;break}
    }
    $stagingFolder=Join-Path $workDir ('expert-import-'+$v+'-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $stagingFolder -Force)
    $package=Join-Path $stagingFolder $file.Name
    $signature=$package+'.asc';$key=Join-Path $stagingFolder 'torbrowser-developers-public.asc'
    Copy-Item -LiteralPath $file.FullName -Destination $package -ErrorAction Stop
    Copy-Item -LiteralPath $sigSource -Destination $signature -ErrorAction Stop
    if($keySource){Copy-Item -LiteralPath $keySource -Destination $key -ErrorAction Stop}
    else {
        Write-Output 'No signing key in import folder; trying the pinned-fingerprint key service.'
        $null=Receive-VeylDownload ('https://keys.openpgp.org/vks/v1/by-fingerprint/'+$trustedFingerprint) $key 'Pinned Tor signing key' @('keys.openpgp.org')
    }
    return [pscustomobject]@{Version=$v;Package=$package;Signature=$signature;Key=$key;Source=('Imported signed bundle from '+[IO.Path]::GetFullPath($Folder))}
}

function Test-Payload([string]$Folder) {
    foreach ($file in @('tor\tor.exe','tor\pluggable_transports\lyrebird.exe','data\geoip','data\geoip6')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Folder $file) -PathType Leaf)) { throw "Expert Bundle layout missing: $file" }
    }
}
function Assert-TargetRoot {
    if (-not (Test-Path -LiteralPath (Join-Path $rootPath '_internal\Start-TorTunnel.ps1') -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $rootPath 'VERSION.txt') -PathType Leaf)) { throw 'Target is not a valid TorTunnel Universal installation.' }
}
Assert-TargetRoot
if (-not (Test-Path -LiteralPath $workDir)) { [void](New-Item -ItemType Directory -Path $workDir -Force) }
. (Join-Path $PSScriptRoot 'TorTunnel.TransferProgress.ps1')
Initialize-VeylProgress $rootPath $(switch($Action){'Prepare'{'UpdatePrepare'}'Install'{'UpdateInstall'}'Rollback'{'UpdateRollback'}})
if ($Action -eq 'Prepare') {
  try {
    # Import requires an original signed archive, its .asc and a Tor Developers
    # key file; the pinned fingerprint and detached signature are always checked.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    if(-not [string]::IsNullOrWhiteSpace($SourceDirectory)){
        Set-PrepareStage 'Importing a signed Windows Expert Bundle' 'Running'
        $import=Copy-SignedImport $SourceDirectory
        $versionTag=[string]$import.Version
        $package=[string]$import.Package
        $signature=[string]$import.Signature
        $key=[string]$import.Key
        $uri=[string]$import.Source
        Write-Output ('Imported archive for cryptographic verification: '+$package)
    }else{
        Set-PrepareStage 'Discovering the official distribution directory' 'Running'
        $found=Get-OfficialWindowsBundle
        $versionTag=[string]$found.Version
        $uri=[string]$found.Url
        $folder=Join-Path $workDir ('expert-'+$versionTag+'-'+[guid]::NewGuid().ToString('N'))
        [void](New-Item -ItemType Directory -Path $folder -Force)
        $name=[IO.Path]::GetFileName(([uri]$uri).AbsolutePath)
        $package=Join-Path $folder $name
        $signature=$package+'.asc'
        Set-PrepareStage 'Downloading the signed Tor archive' 'Running'
        Write-Output ('Official signed Windows Expert Bundle release: '+$versionTag)
        $null=Receive-VeylDownload $uri $package 'Tor Windows Expert Bundle' @('dist.torproject.org')
        Set-PrepareStage 'Downloading the detached signature' 'Running'
        $null=Receive-VeylDownload ($uri+'.asc') $signature 'Tor bundle detached signature' @('dist.torproject.org')
        $key=Join-Path $folder 'torbrowser-developers-public.asc'
        Set-PrepareStage 'Acquiring the pinned Tor signing key' 'Running'
        $null=Receive-VeylDownload ('https://keys.openpgp.org/vks/v1/by-fingerprint/'+$trustedFingerprint) $key 'Pinned Tor signing key' @('keys.openpgp.org')
    }
    if ((Get-Item -LiteralPath $package).Length -lt 102400 -or (Get-Item -LiteralPath $signature).Length -lt 100) { throw 'Bundle/signature download was unexpectedly small.' }
    if((Get-Item -LiteralPath $key).Length -lt 200){throw 'Tor signing key download was too small.'}
    Set-PrepareStage 'Verifying the OpenPGP signature' 'Running'
    Assert-Signature $package $signature $key
    Set-PrepareStage 'Inspecting signed archive paths' 'Running'
    $tar = Assert-SafeEntries $package
    $data = [ordered]@{ format=1; status='Verified'; verifiedAt=(Get-Date).ToString('o'); sourceUrl=$uri; package=$package;
        signature=$signature; publicKey=$key; publicKeySha256=(Get-FileHash -LiteralPath $key -Algorithm SHA256).Hash; signatureFingerprint=$trustedFingerprint; sha256=(Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash;
        expertBundle=$versionTag }
    Save-Json $marker $data
    Set-PrepareStage 'Verified bundle staged' 'Succeeded' ('Tor Expert Bundle '+$versionTag+' is ready for approved installation: '+$package)
    Write-Output "STAGED AND VERIFIED: $versionTag. Choose 'Install verified' after disconnecting TorTunnel."
    exit 0
  }catch{
    $reason=$_.Exception.Message
    try{Set-PrepareStage $script:PrepareStage 'Failed' $reason}catch{}
    throw
  }
}
if ($Action -eq 'Install') {
    Write-VeylProgress 'Checking the signed candidate and stopped tunnel' 'Running' 0 -1 $torDir 'The signed candidate and offline requirements must pass.'
    Assert-Offline
    $data = Verify-PackageRecord
    $package = [IO.Path]::GetFullPath([string]$data.package)
    $tar = Assert-SafeEntries $package
    $extract = Join-Path $workDir ('extract-'+[guid]::NewGuid().ToString('N'))
    $stage = Join-Path $rootPath ('Tor.update-stage-'+[guid]::NewGuid().ToString('N'))
    $backup = Join-Path $rootPath ('Tor.update-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    [void](New-Item -ItemType Directory -Path $extract -Force)
    $swapped = $false
    $oldMoved = $false
    try {
        Write-Output 'Extracting signature-verified Expert Bundle to isolated staging...'
        Write-VeylProgress 'Extracting signature-verified Tor bundle' 'Running' 0 -1 $extract 'Extracting to an isolated folder; active Tor files are unchanged.'
        & $tar -xzf $package -C $extract
        if ($LASTEXITCODE -ne 0) { throw 'Expert Bundle extraction failed.' }
        Test-Payload $extract
        # Preserve local non-bundle files and the original Tor directory until final promotion.
        $hadTor=(Test-Path -LiteralPath $torDir -PathType Container)
        if($hadTor) { Copy-Item -LiteralPath $torDir -Destination $stage -Recurse -Force -ErrorAction Stop }
        else { [void](New-Item -ItemType Directory -Path $stage -Force) }
        foreach ($item in (Get-ChildItem -LiteralPath $extract -Recurse -File -ErrorAction Stop)) {
            $rel = $item.FullName.Substring($extract.Length).TrimStart([char]'\')
            # Signed documentation and other harmless archive extras are not
            # part of the Tor runtime. Only promote tor/ and data/ payloads.
            if (-not ($rel.StartsWith('tor\', [StringComparison]::OrdinalIgnoreCase) -or
                        $rel.StartsWith('data\', [StringComparison]::OrdinalIgnoreCase))) { continue }
            $dest = Join-Path $stage $rel
            $dir = Split-Path -Parent $dest
            if (-not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir -Force) }
            Copy-Item -LiteralPath $item.FullName -Destination $dest -Force -ErrorAction Stop
        }
        Test-Payload $stage
        $version = Get-Version (Join-Path $stage 'tor\tor.exe')
        $oldVersion=$null
        if($hadTor) {
            $oldExe=Join-Path $torDir 'tor\tor.exe'
            if(-not(Test-Path -LiteralPath $oldExe)){ $oldExe=Join-Path $torDir 'tor.exe' }
            if(Test-Path -LiteralPath $oldExe){ $oldVersion=Get-Version $oldExe }
        }
        if($oldVersion -and [version]$version -le [version]$oldVersion) { throw "Refusing a non-newer Tor binary: staged=$version, installed=$oldVersion" }
        Write-Output "Staged Tor version: $version. Installed: $oldVersion."
        Assert-Offline
        Write-VeylProgress 'Promoting tested Tor files to installation' 'Running' 0 -1 $torDir 'Original files are retained for rollback; promoting only after payload checks.'
        if($hadTor){ [IO.Directory]::Move($torDir,$backup); $oldMoved=$true }
        [IO.Directory]::Move($stage,$torDir)
        $swapped = $true
        if ((Get-Version (Join-Path $torDir 'tor\tor.exe')) -ne $version) { throw 'Activated Tor binary version does not match the verified candidate.' }
        # Always issue an installation receipt, including for first installs.
        # A fresh install has no previous Tor directory and is not rollbackable.
        $receipt = [ordered]@{format=1; installedAt=(Get-Date).ToString('o'); previousVersion=$oldVersion; installedVersion=$version;
            rollbackAvailable=[bool]$hadTor; originalDirectory=$(if($hadTor){$backup}else{''});
            activeDirectory=$torDir; packageSha256=$data.sha256 }
        Save-Json $installMarker $receipt
        if(-not $hadTor){Write-Output 'Fresh installation: no previous Tor directory exists to roll back to.'}
        Write-Output 'SIGNED TOR BUNDLE INSTALLED. Existing Tor folder retained for rollback if one was present.'
        Write-VeylProgress 'Tor bundle installed and executable version checked' 'Completed' 0 -1 $torDir ('Installed Tor '+$version+' at '+$torDir+'. Next: run Preflight to test real operation.')
        Write-Output 'Run TorTunnel Preflight and connect with Health Check to confirm full operational compatibility.'
    }
    catch {
        $reason = $_.Exception.Message
        if($swapped -and -not $oldMoved) {
            try { [IO.Directory]::Move($torDir,(Join-Path $rootPath ('Tor.failed-update-'+[guid]::NewGuid().ToString('N')))) } catch { $reason += ' | failed fresh-install cleanup: '+$_.Exception.Message }
        }
        if ($oldMoved) {
            try {
                if ($swapped -and (Test-Path -LiteralPath $torDir)) {
                    $failedDir = Join-Path $rootPath ('Tor.failed-update-'+[guid]::NewGuid().ToString('N'))
                    [IO.Directory]::Move($torDir,$failedDir)
                }
                if (Test-Path -LiteralPath $backup) { [IO.Directory]::Move($backup,$torDir) }
            } catch { $reason += ' | CRITICAL ROLLBACK ERROR: ' + $_.Exception.Message }
        }
        try{Write-VeylProgress $script:VeylProgressStage 'Failed' 0 -1 $torDir $reason}catch{}
        throw ('Update not completed. ' + $reason)
    }
    finally {
        if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
    exit 0
}
if ($Action -eq 'Rollback') {
    Write-VeylProgress 'Restoring backed-up Tor binaries' 'Running' 0 -1 $torDir 'Requires a stopped tunnel and a valid previous installation.'
    Assert-Offline
    $receipt = Read-Json $installMarker
    if($receipt.PSObject.Properties.Name -contains 'rollbackAvailable' -and -not [bool]$receipt.rollbackAvailable){
        throw 'This was a fresh installation, so there is no previous Tor version to restore.'
    }
    if([string]::IsNullOrWhiteSpace([string]$receipt.originalDirectory)){
        throw 'No previous Tor backup directory was recorded; rollback is not available.'
    }
    $backup = [IO.Path]::GetFullPath([string]$receipt.originalDirectory)
    if (-not $backup.StartsWith($rootPath.TrimEnd('\')+'\Tor.update-backup-',[StringComparison]::OrdinalIgnoreCase)) { throw 'Recorded rollback directory is outside the expected installation backup name.' }
    if (-not (Test-Path -LiteralPath $backup -PathType Container)) { throw 'Original Tor folder is missing; cannot roll back.' }
    $reverted = Join-Path $rootPath ('Tor.reverted-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    [IO.Directory]::Move($torDir,$reverted)
    try {
        [IO.Directory]::Move($backup,$torDir)
        $restored = Get-Version (Join-Path $torDir 'tor\tor.exe')
        if ($restored -ne [string]$receipt.previousVersion) { throw 'Restored Tor version does not match backup metadata.' }
        Remove-Item -LiteralPath $installMarker -Force -ErrorAction Stop
        Write-Output "ROLLBACK COMPLETE: Tor $restored restored. Replaced candidate retained at $reverted."
        Write-VeylProgress 'Tor rollback verified' 'Completed' 0 -1 $torDir ('Restored Tor '+$restored+' at '+$torDir+'. Run Preflight before connecting.')
    } catch {
        $reason = $_.Exception.Message
        try {
            if (Test-Path -LiteralPath $torDir) { [IO.Directory]::Move($torDir,(Join-Path $rootPath ('Tor.failed-rollback-'+[guid]::NewGuid().ToString('N')))) }
            [IO.Directory]::Move($reverted,$torDir)
        } catch { $reason += ' | CRITICAL RESTORE FAILURE: '+$_.Exception.Message }
        try{Write-VeylProgress $script:VeylProgressStage 'Failed' 0 -1 $torDir $reason}catch{}
        throw $reason
    }
    exit 0
}
