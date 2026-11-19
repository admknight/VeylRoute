# TorTunnel Universal Control Center: in-app Tor OpenPGP verifier.
# Does NOT require Gpg4win, GnuPG, NuGet CLI or an external application install.
# Automatically retrieves an internal managed verification library when first needed.
# Requires Windows PowerShell 5.1, .NET Framework 4.6.1+, HTTPS and Internet access on first use.
# Verification is fail-closed: unsupported signatures, missing dependencies and failed subkey bindings abort.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$Package,
    [Parameter(Mandatory=$true)][string]$Signature,
    [Parameter(Mandatory=$true)][string]$PublicKey
)
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath($Root)
$expectedPrimary='EF6E286DDA85EA2A4BA7DE684E2C6E8793298290'
$libVer='2.6.2'
$libBase='https://api.nuget.org/v3-flatcontainer/bouncycastle.cryptography/'+$libVer+'/'
$libName='bouncycastle.cryptography.'+$libVer+'.nupkg'
$libRoot=Join-Path $rootPath '_internal\lib\openpgp'
$libPath=Join-Path $libRoot 'BouncyCastle.Cryptography.dll'
$receiptPath=Join-Path $libRoot 'library-receipt.json'
$utf8=New-Object Text.UTF8Encoding($false)
function Assert-LocalFile([string]$Path){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "Missing verification input: $Path"}
}
function Get-Sha256([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()}
function Install-ManagedLibrary {
    # NuGet-hosted BouncyCastle.Cryptography is a library used inside this app, not a separate installed tool.
    # Download the package and its published digest over HTTPS, then compare before loading code.
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $stage=Join-Path $libRoot ('stage-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    try {
        $pkg=Join-Path $stage $libName
        # NuGet's flat-container API publishes .nupkg and .nuspec, NOT an
        # internet-accessible .nupkg.sha512 file. The SHA-512 is published in
        # the package's official NuGet catalog entry. Fetch both over HTTPS.
        $packageUri=$libBase+$libName
        $registrationUri='https://api.nuget.org/v3/registration5-semver1/bouncycastle.cryptography/'+$libVer+'.json'
        Write-Output 'Preparing built-in OpenPGP verification component (no external installer)...'
        Write-Output 'Reading the published NuGet catalog SHA-512 for the pinned cryptography library...'
        try {
            $registration=Invoke-RestMethod -Uri $registrationUri -TimeoutSec 40 -ErrorAction Stop
        }catch { throw ('Could not retrieve official NuGet package metadata: '+$_.Exception.Message) }
        if([string]$registration.packageContent -cne $packageUri){
            throw 'NuGet registration returned an unexpected package-content URL.'
        }
        $catalogUrl=if($registration.catalogEntry -is [string]){
            [string]$registration.catalogEntry
        }else{
            [string]$registration.catalogEntry.'@id'
        }
        if(-not $catalogUrl){throw 'NuGet registration did not provide a catalog entry URL.'}
        try {$catalogUri=[uri]$catalogUrl}catch {throw 'NuGet catalog entry URL was invalid.'}
        if(-not $catalogUri.IsAbsoluteUri -or $catalogUri.Scheme -cne 'https' -or
            $catalogUri.Host -cne 'api.nuget.org' -or -not $catalogUri.AbsolutePath.StartsWith('/v3/catalog0/data/',[StringComparison]::Ordinal) -or
            -not $catalogUri.AbsolutePath.EndsWith('/bouncycastle.cryptography.'+$libVer+'.json',[StringComparison]::Ordinal) -or
            -not [string]::IsNullOrEmpty($catalogUri.Query) -or -not [string]::IsNullOrEmpty($catalogUri.Fragment)){
            throw 'NuGet catalog metadata pointed outside the approved official catalog.'
        }
        try {
            $catalog=Invoke-RestMethod -Uri $catalogUri.AbsoluteUri -TimeoutSec 40 -ErrorAction Stop
        }catch {throw ('Could not retrieve official NuGet catalog hash: '+$_.Exception.Message)}
        if([string]$catalog.id -cne 'BouncyCastle.Cryptography' -or
           [string]$catalog.version -cne $libVer -or
           [string]$catalog.packageHashAlgorithm -cne 'SHA512'){
            throw 'NuGet catalog identity, version, or hash algorithm did not match the pinned library.'
        }
        $expectedDigest=([string]$catalog.packageHash).Trim()
        try {$expectedBytes=[Convert]::FromBase64String($expectedDigest)}catch{throw 'The NuGet catalog SHA512 value was invalid.'}
        if($expectedBytes.Length -ne 64){throw 'NuGet catalog SHA512 value did not decode to 64 bytes.'}
        $expectedPackageSize=[long]$catalog.packageSize
        if($expectedPackageSize -lt 100000){throw 'NuGet catalog package size was not valid.'}
        Invoke-WebRequest -Uri $packageUri -UseBasicParsing -OutFile $pkg -TimeoutSec 150 -ErrorAction Stop
        if((Get-Item -LiteralPath $pkg).Length -ne $expectedPackageSize){throw 'NuGet package size did not match its official catalog metadata.'}
        $sha=[Security.Cryptography.SHA512]::Create()
        try {
            $in=[IO.File]::OpenRead($pkg)
            try {$actualBytes=$sha.ComputeHash($in)}finally{$in.Dispose()}
        }finally{$sha.Dispose()}
        $actualDigest=[Convert]::ToBase64String($actualBytes)
        if($actualDigest -cne $expectedDigest){throw 'Managed verification library package SHA512 mismatch.'}
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive=[IO.Compression.ZipFile]::OpenRead($pkg)
        try {
            $entries=@($archive.Entries | Where-Object {$_.FullName.Replace('\','/') -ceq 'lib/net461/BouncyCastle.Cryptography.dll'})
            if($entries.Count -ne 1 -or $entries[0].Length -lt 100000){throw 'Expected .NET Framework crypto DLL missing from verified NuGet package.'}
            $tempDll=Join-Path $stage 'BouncyCastle.Cryptography.dll'
            $in=$entries[0].Open();$out=[IO.File]::Open($tempDll,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
            try{$in.CopyTo($out)}finally{$out.Dispose();$in.Dispose()}
        }finally{$archive.Dispose()}
        $dllHash=Get-Sha256 $tempDll
        $saved=[ordered]@{package='BouncyCastle.Cryptography';version=$libVer;source='https://api.nuget.org/';catalogUrl=$catalogUri.AbsoluteUri;packageSha512=$actualDigest;dllSha256=$dllHash;installedAt=(Get-Date).ToUniversalTime().ToString('o')}
        $tmpReceipt=Join-Path $stage 'library-receipt.json'
        [IO.File]::WriteAllText($tmpReceipt,($saved|ConvertTo-Json -Depth 4),$utf8)
        # Never overwrite a different existing DLL without recording it separately.
        if(Test-Path -LiteralPath $libPath){
            $old=Join-Path $libRoot ('BouncyCastle.previous-'+[guid]::NewGuid().ToString('N')+'.dll')
            [IO.File]::Move($libPath,$old)
        }
        [IO.File]::Move($tempDll,$libPath)
        Copy-Item -LiteralPath $tmpReceipt -Destination $receiptPath -Force -ErrorAction Stop
        if((Get-Sha256 $libPath) -ne $dllHash){throw 'Installed managed verifier hash changed unexpectedly.'}
        Write-Output 'Built-in OpenPGP verifier component acquired and checked.'
    }finally{
        if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue}
    }
}
function Assert-ManagedLibrary {
    if(-not(Test-Path -LiteralPath $libRoot)){New-Item -ItemType Directory -Path $libRoot -Force|Out-Null}
    $valid=$false
    if((Test-Path -LiteralPath $libPath -PathType Leaf) -and (Test-Path -LiteralPath $receiptPath -PathType Leaf)){
        try{
            $r=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $valid=([string]$r.package -ceq 'BouncyCastle.Cryptography' -and [string]$r.version -ceq $libVer -and [string]$r.dllSha256 -ceq (Get-Sha256 $libPath))
        }catch{$valid=$false}
    }
    if(-not $valid){Install-ManagedLibrary}
    $r=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -ErrorAction Stop
    if([string]$r.version -cne $libVer -or [string]$r.dllSha256 -cne (Get-Sha256 $libPath)){throw 'OpenPGP managed verifier integrity check failed.'}
    Add-Type -Path $libPath -ErrorAction Stop
}
function Get-Fingerprint([byte[]]$Bytes){return (-join @($Bytes | ForEach-Object {$_.ToString('X2')}))}
function Assert-KeyNotRevoked($Key,$Master,[int]$RevocationType){
    foreach($rev in @($Key.GetSignaturesOfType($RevocationType))){
        $rev.InitVerify($Master)
        if($Key.IsMasterKey){$isRevoked=$rev.VerifyCertification($Key)}
        else{$isRevoked=$rev.VerifyCertification($Master,$Key)}
        if($isRevoked){throw 'Tor signing key has a valid revocation. Refusing installation.'}
    }
}
Assert-LocalFile $Package
Assert-LocalFile $Signature
Assert-LocalFile $PublicKey
Assert-ManagedLibrary
$keyStream=[IO.File]::OpenRead($PublicKey)
try{
    $decoder=[Org.BouncyCastle.Bcpg.OpenPgp.PgpUtilities]::GetDecoderStream($keyStream)
    $bundle=[Org.BouncyCastle.Bcpg.OpenPgp.PgpPublicKeyRingBundle]::new($decoder)
    $trustedRings=@()
    foreach($ring in $bundle.GetKeyRings()){
        $master=$ring.GetPublicKey()
        if($null -ne $master -and (Get-Fingerprint ($master.GetFingerprint())) -ceq $expectedPrimary){$trustedRings+=@($ring)}
    }
    if($trustedRings.Count -ne 1){throw 'Tor Developers primary public key fingerprint did not match the pinned key.'}
    $trustedRing=$trustedRings[0]
    $master=$trustedRing.GetPublicKey()
    Assert-KeyNotRevoked $master $master 32
}finally{$keyStream.Dispose()}
$sigStream=[IO.File]::OpenRead($Signature)
try{
    $decodedSig=[Org.BouncyCastle.Bcpg.OpenPgp.PgpUtilities]::GetDecoderStream($sigStream)
    $factory=[Org.BouncyCastle.Bcpg.OpenPgp.PgpObjectFactory]::new($decodedSig)
    $sigObject=$null
    for($i=0;$i -lt 8;$i++){
        $next=$factory.NextPgpObject()
        if($null -eq $next){break}
        if($next -is [Org.BouncyCastle.Bcpg.OpenPgp.PgpSignatureList]){$sigObject=$next;break}
    }
    if($null -eq $sigObject -or $sigObject.Count -ne 1){throw 'Expected exactly one detached OpenPGP signature.'}
    $sig=$sigObject[0]
    if($sig.SignatureType -ne 0){throw 'Tor archive signature is not a binary-document signature.'}
    if([int]$sig.HashAlgorithm -notin @(8,9,10)){throw 'Tor archive signature does not use SHA-256 or stronger.'}
    $signer=$trustedRing.GetPublicKey($sig.KeyId)
    if($null -eq $signer){throw 'The package signature does not belong to the pinned Tor signing-key family.'}
    $created=$sig.CreationTime.ToUniversalTime()
    if($created -gt [DateTime]::UtcNow.AddMinutes(15)){throw 'Package signature time is unexpectedly in the future.'}
    if($created -lt $signer.CreationTime.ToUniversalTime()){throw 'Package signature predates its signing key.'}
    $validSecs=[long]$signer.GetValidSeconds()
    if($validSecs -gt 0 -and $created -gt $signer.CreationTime.ToUniversalTime().AddSeconds($validSecs)){
        throw 'Signing key was expired when the package was signed.'
    }
    if(-not $signer.IsMasterKey){
        $bound=$false
        foreach($binding in @($signer.GetSignaturesOfType(24))){
            try{
                $binding.InitVerify($master)
                if($binding.VerifyCertification($master,$signer) -and $binding.CreationTime.ToUniversalTime() -le $created){$bound=$true;break}
            }catch{}
        }
        if(-not $bound){throw 'Signing subkey is not cryptographically bound to the pinned Tor primary key.'}
        Assert-KeyNotRevoked $signer $master 40
    }
    $sig.InitVerify($signer)
    $payload=[IO.File]::OpenRead($Package)
    try{
        $buffer=New-Object byte[] (65536)
        while(($read=$payload.Read($buffer,0,$buffer.Length)) -gt 0){$sig.Update($buffer,0,$read)}
    }finally{$payload.Dispose()}
    if(-not $sig.Verify()){throw 'Detached OpenPGP signature verification FAILED. The Tor package was not installed.'}
    Write-Output ('OpenPGP signature: VERIFIED by built-in cryptography; pinned primary fingerprint '+$expectedPrimary)
}finally{$sigStream.Dispose()}
