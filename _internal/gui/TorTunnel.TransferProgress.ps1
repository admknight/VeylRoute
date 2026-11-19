# VeylRoute: runtime-only progress telemetry for portable component operations.
# No networking, security, or routing policy is changed by this helper.
$script:VeylProgressFile = ''
$script:VeylProgressAction = ''
$script:VeylProgressStage = 'Starting'
$script:VeylProgressUtf8 = [System.Text.UTF8Encoding]::new($false)
function Initialize-VeylProgress([string]$Root,[string]$Action) {
    $dir = Join-Path $Root 'runtime\gui'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:VeylProgressFile = Join-Path $dir 'component-progress.json'
    $script:VeylProgressAction = $Action
    Write-VeylProgress 'Starting component operation' 'Running' 0 -1 '' 'Preparing the verified component workflow.'
}
function Write-VeylProgress([string]$Stage,[string]$State='Running',[long]$Bytes=0,[long]$Total=-1,[string]$Destination='',[string]$Detail='') {
    $script:VeylProgressStage = $Stage
    if (-not $script:VeylProgressFile) { return }
    $percent = -1
    if ($Total -gt 0) { $percent = [int][math]::Max(0,[math]::Min(100,[math]::Floor(100.0*$Bytes/$Total))) }
    if ($State -eq 'Completed') { $percent = 100 }
    $data = [ordered]@{ format=1; action=$script:VeylProgressAction; state=$State;
        stage=$Stage; percent=$percent; bytes=$Bytes; total=$Total;
        destination=$Destination; detail=$Detail; updatedUtc=(Get-Date).ToUniversalTime().ToString('o') }
    $tmp = $script:VeylProgressFile+'.tmp-'+[guid]::NewGuid().ToString('N')
    $bak = $script:VeylProgressFile+'.bak-'+[guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllText($tmp,(($data|ConvertTo-Json -Depth 5)+"`r`n"),$script:VeylProgressUtf8)
        # Replace with an actual non-null backup path. Windows readers may briefly
        # lock a progress record, so retry boundedly instead of losing all telemetry.
        $committed=$false
        $lastError=''
        for($attempt=0;$attempt -lt 5;$attempt++){
            try {
                if([IO.File]::Exists($script:VeylProgressFile)){
                    [IO.File]::Replace($tmp,$script:VeylProgressFile,$bak)
                }else{[IO.File]::Move($tmp,$script:VeylProgressFile)}
                $committed=$true;break
            }catch{
                $lastError=$_.Exception.Message
                Start-Sleep -Milliseconds 100
            }
        }
        if(-not $committed){
            # Telemetry alone may use a non-atomic fallback. The GUI safely retries
            # incomplete JSON reads; component installation still requires hashes.
            try{
                Move-Item -LiteralPath $tmp -Destination $script:VeylProgressFile -Force -ErrorAction Stop
                $committed=$true
            }catch{throw ("Unable to persist component progress: $lastError | fallback: "+$_.Exception.Message)}
        }
    } finally {
        foreach($file in @($tmp,$bak)){
            if([IO.File]::Exists($file)){try{[IO.File]::Delete($file)}catch{}}
        }
    }
}
function Receive-VeylDownload([string]$Url,[string]$Destination,[string]$Label,[string[]]$AllowedHosts) {
    $uri = [uri]$Url
    if ($uri.Scheme -ne 'https' -or $uri.Host -notin $AllowedHosts) { throw "Download source not approved for $Label." }
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (Test-Path -LiteralPath $Destination) { throw "Download destination already exists: $Destination" }
    $temp = $Destination+'.partial-'+[guid]::NewGuid().ToString('N')
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $request = [Net.HttpWebRequest][Net.WebRequest]::Create($uri)
    $request.Method = 'GET'
    $request.Timeout = 25000
    $request.ReadWriteTimeout = 25000
    # Bounded wall-clock transfer time. Larger Tor archives can take longer than helpers.
    $maxSeconds = if($Label -eq 'Tor Windows Expert Bundle'){600}else{150}
    $elapsed=[Diagnostics.Stopwatch]::StartNew()
    $request.AllowAutoRedirect = $true
    $request.MaximumAutomaticRedirections = 5
    $request.UserAgent = 'VeylRoute/2.8 (Windows portable component setup)'
    $response=$null; $source=$null; $target=$null; $done=0L; $size=-1L
    try {
        Write-VeylProgress ('Connecting: '+$Label) 'Running' 0 -1 $Destination 'Establishing an HTTPS connection.'
        $response=$request.GetResponse()
        $final=[uri]$response.ResponseUri
        if ($final.Scheme -ne 'https' -or $final.Host -notin $AllowedHosts) { throw "The $Label download redirected to an unapproved host: $($final.Host)" }
        $size=[long]$response.ContentLength
        $source=$response.GetResponseStream()
        $target=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 131072
        $last=[datetime]::UtcNow.AddSeconds(-1)
        while (($read=$source.Read($buffer,0,$buffer.Length)) -gt 0) {
            if($elapsed.Elapsed.TotalSeconds -gt $maxSeconds){throw "Download time limit reached for $Label ($maxSeconds seconds). No component was installed."}
            $target.Write($buffer,0,$read)
            $done += $read
            if (([datetime]::UtcNow-$last).TotalMilliseconds -ge 350) {
                Write-VeylProgress ('Downloading: '+$Label) 'Running' $done $size $Destination 'Bytes actually received; file is not installed yet.'
                $last=[datetime]::UtcNow
            }
        }
        $target.Flush(); $target.Dispose(); $target=$null
        if($elapsed.Elapsed.TotalSeconds -gt $maxSeconds){throw "Download time limit reached for $Label ($maxSeconds seconds). No component was installed."}
        if($done -le 0 -or ($size -gt 0 -and $done -ne $size)){throw "Incomplete $Label download: received $done of $size bytes."}
        [IO.File]::Move($temp,$Destination)
        Write-VeylProgress ('Downloaded: '+$Label) 'Running' $done $done $Destination 'Archive downloaded; cryptographic/format checks still required.'
        return $Destination
    } finally {
        if($target){$target.Dispose()}
        if($source){$source.Dispose()}
        if($response){$response.Dispose()}
        if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
    }
}
