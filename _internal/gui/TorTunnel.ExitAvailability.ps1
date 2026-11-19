# Read-only public Tor exit-relay availability check. Does not configure networking.
[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($Root)){throw 'Portable root is required.'}
$rootPath=[IO.Path]::GetFullPath($Root)
$outDir=Join-Path $rootPath 'runtime\gui'
if(-not(Test-Path -LiteralPath $outDir -PathType Container)){
    [void](New-Item -ItemType Directory -Force -Path $outDir)
}
$cacheFile=Join-Path $outDir 'exit-availability.json'
# Current running relays carrying the Exit flag. This is NOT an end-to-end test
# that a Tor exit will allow every destination or will complete circuit setup.
$source='https://onionoo.torproject.org/details?type=relay&running=true&flag=Exit&fields=country'
try {
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $data=Invoke-RestMethod -Uri $source -Method Get -TimeoutSec 25 -UseBasicParsing -ErrorAction Stop
    $relays=@($data.relays)
    if($relays.Count -lt 1){throw 'Tor Project returned no running Exit-flag relay records; availability cannot be confirmed.'}
    $published=[string]$data.relays_published
    $publishedUtc=[datetime]::ParseExact($published,'yyyy-MM-dd HH:mm:ss',([Globalization.CultureInfo]::InvariantCulture),([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal))
    if(([datetime]::UtcNow-$publishedUtc).TotalHours -gt 6 -or $publishedUtc -gt [datetime]::UtcNow.AddMinutes(15)){
        throw 'Tor Project relay information is outside the permitted freshness window.'
    }
    $counts=[ordered]@{}
    foreach($relay in $relays){
        $code=([string]$relay.country).ToLowerInvariant()
        if($code -match '^[a-z]{2}$'){
            if(-not $counts.Contains($code)){$counts[$code]=0}
            $counts[$code]++
        }
    }
    if($counts.Count -eq 0){throw 'Relay country information was missing or invalid.'}
    $record=[ordered]@{
        format=1
        source='Tor Project Onionoo running relays with Exit flag'
        requestedUrl=$source
        fetchedAtUtc=([datetime]::UtcNow.ToString('o'))
        relaysPublishedUtc=$publishedUtc.ToString('o')
        totalRunningExits=[int]$relays.Count
        counts=$counts
    }
    $json=$record|ConvertTo-Json -Depth 6
    $utf8=New-Object System.Text.UTF8Encoding($false)
    $tmp=$cacheFile+'.tmp-'+[guid]::NewGuid().ToString('N')
    try{
        [IO.File]::WriteAllText($tmp,($json+"`r`n"),$utf8)
        if(Test-Path -LiteralPath $cacheFile -PathType Leaf){Move-Item -LiteralPath $tmp -Destination $cacheFile -Force}
        else{[IO.File]::Move($tmp,$cacheFile)}
    }finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}}
    Write-Host 'Tor Project running Exit relay snapshot downloaded.'
    Write-Host ('Relay publication UTC : '+$publishedUtc.ToString('u'))
    Write-Host ('Running Exit relays    : '+$relays.Count)
    Write-Host ('Countries with exits   : '+$counts.Count)
    foreach($code in @('us','pk')){Write-Host (('Exit '+$code.ToUpperInvariant()).PadRight(20)+' : '+$(if($counts.Contains($code)){$counts[$code]}else{0}))}
    Write-Host 'This is a snapshot of Exit-flag relays, not a guarantee of working circuits or website reachability.'
}catch{
    Write-Host ('EXIT AVAILABILITY FAILED: '+$_.Exception.Message)
    exit 1
}
