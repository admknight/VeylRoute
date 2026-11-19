# VeylRoute H5 - single, user-initiated Tor NEWNYM request.
# Does not modify Windows routes, firewall, DNS or session state.
[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference='Stop'
$internal=[IO.Path]::GetFullPath($PSScriptRoot)
if([string]::IsNullOrWhiteSpace($Root)){$Root=[IO.Path]::GetFullPath((Split-Path -Parent $internal))}
else{$Root=[IO.Path]::GetFullPath($Root.TrimEnd('\'))}
. (Join-Path $internal 'TorTunnel.Common.ps1')

function Assert-TTControlResponse([string[]]$Lines,[string]$Step){
    if(@($Lines).Count -lt 1 -or $Lines[-1] -ne '250 OK'){
        throw ('Tor rejected '+$Step+'. The connection was not changed by VeylRoute.')
    }
}
function Read-TTControlReply([IO.StreamReader]$Reader){
    $lines=New-Object 'System.Collections.Generic.List[string]'
    for($i=0;$i -lt 40;$i++){
        $line=$Reader.ReadLine()
        if($null -eq $line){throw 'Tor closed its control connection unexpectedly.'}
        if($line -notmatch '^\d{3}[-+ ]'){throw 'Unrecognized Tor control reply.'}
        if($line.Substring(3,1) -eq '+'){throw 'Unexpected multi-line Tor control payload.'}
        $lines.Add($line)
        if($line.Substring(3,1) -eq ' '){return $lines.ToArray()}
    }
    throw 'Tor control reply exceeded the bounded limit.'
}
function Invoke-TTControlCommand([IO.StreamWriter]$Writer,[IO.StreamReader]$Reader,[string]$Command){
    $Writer.Write($Command+"`r`n")
    $Writer.Flush()
    return (Read-TTControlReply $Reader)
}
function Convert-TTHex([byte[]]$Bytes){return [BitConverter]::ToString($Bytes).Replace('-','')}
function ConvertFrom-TTHex([string]$Value){
    if($Value -notmatch '^(?:[0-9a-fA-F]{2})+$'){throw 'Invalid Tor control authentication value.'}
    $result=New-Object byte[] ($Value.Length / 2)
    for($i=0;$i -lt $result.Length;$i++){$result[$i]=[Convert]::ToByte($Value.Substring($i*2,2),16)}
    return ,$result
}
function Get-TTSafeCookieHmac([string]$Purpose,[byte[]]$Cookie,[byte[]]$ClientNonce,[byte[]]$ServerNonce){
    $payload=New-Object byte[] 96
    [Array]::Copy($Cookie,0,$payload,0,32)
    [Array]::Copy($ClientNonce,0,$payload,32,32)
    [Array]::Copy($ServerNonce,0,$payload,64,32)
    $hmac=[System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::ASCII.GetBytes($Purpose))
    try{return ,($hmac.ComputeHash($payload))}finally{$hmac.Dispose();[Array]::Clear($payload,0,$payload.Length)}
}
function Test-TTBytesMatch([byte[]]$Left,[byte[]]$Right){
    if($Left.Length -ne $Right.Length){return $false}
    $diff=0
    for($i=0;$i -lt $Left.Length;$i++){$diff=$diff -bor ($Left[$i] -bxor $Right[$i])}
    return ($diff -eq 0)
}

try{
    $statePath=Join-Path $Root 'runtime\session-state.json'
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw 'No active VeylRoute session. Connect first.'}
    $state=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if(-not [string]::Equals([IO.Path]::GetFullPath([string]$state.RootPath),$Root,[StringComparison]::OrdinalIgnoreCase)){
        throw 'Session root differs from this installation.'
    }
    if([string]$state.MachineGuid -ne (Get-TTMachineGuid)){throw 'Session belongs to a different machine. No control request was sent.'}
    $expectedPortFile=Join-Path $Root 'runtime\tor-control.port'
    $expectedCookieFile=Join-Path $Root 'runtime\tor-data\control_auth_cookie'
    if(-not $state.ControlPortFile -or -not $state.ControlCookieFile){
        throw 'This session predates New Circuit support. Disconnect safely and reconnect using H5 first.'
    }
    if(-not [string]::Equals([IO.Path]::GetFullPath([string]$state.ControlPortFile),$expectedPortFile,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals([IO.Path]::GetFullPath([string]$state.ControlCookieFile),$expectedCookieFile,[StringComparison]::OrdinalIgnoreCase)){
        throw 'Session control paths differ from the current portable root.'
    }
    $torPid=[int]$state.TorPid
    if($torPid -lt 1 -or -not (Get-Process -Id $torPid -ErrorAction SilentlyContinue)){throw 'The managed Tor process is not running.'}
    if(-not $state.TunPid -or -not(Get-Process -Id ([int]$state.TunPid) -ErrorAction SilentlyContinue)){
        throw 'The managed tunnel is not running. Check Health before requesting another circuit.'
    }
    $proc=Get-CimInstance Win32_Process -Filter "ProcessId=$torPid" -ErrorAction Stop
    if(-not $proc -or -not $proc.ExecutablePath -or
       -not [string]::Equals([IO.Path]::GetFullPath([string]$proc.ExecutablePath),[IO.Path]::GetFullPath([string]$state.TorExe),[StringComparison]::OrdinalIgnoreCase)){
        throw 'Tor process ownership could not be verified. Control request was blocked.'
    }
    if(-not(Test-Path -LiteralPath $expectedPortFile -PathType Leaf)){throw 'Control interface unavailable. Disconnect and reconnect with H5.'}
    $portText=[IO.File]::ReadAllText($expectedPortFile)
    $match=[regex]::Match($portText,'(?m)^PORT=127\.0\.0\.1:(\d{2,5})\s*$')
    if(-not $match.Success){throw 'Tor did not report a valid loopback control endpoint.'}
    $port=[int]$match.Groups[1].Value
    if($port -lt 1 -or $port -gt 65535){throw 'Tor control endpoint is invalid.'}
    $owned=@(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction Stop | Where-Object {
        $_.LocalAddress -eq '127.0.0.1' -and [int]$_.OwningProcess -eq $torPid
    })
    if($owned.Count -lt 1){throw 'Control listener is not owned by this session Tor process. No signal was sent.'}

    # Local throttling is in addition to Tor's own optional NEWNYM rate limit.
    $cooldownFile=Join-Path $Root 'runtime\gui\new-circuit-last.json'
    $sameSession=$false
    if(Test-Path -LiteralPath $cooldownFile -PathType Leaf){
        try{
            $recent=Get-Content -LiteralPath $cooldownFile -Raw | ConvertFrom-Json
            $sameSession=([string]$recent.sessionStarted -eq [string]$state.StartedAt)
            if($sameSession){
                $elapsed=([datetime]::UtcNow-([datetime]::Parse([string]$recent.requestedUtc)).ToUniversalTime()).TotalSeconds
                if($elapsed -ge 0 -and $elapsed -lt 15){throw ('Please wait '+[int][Math]::Ceiling(15-$elapsed)+' seconds before another circuit request.')}
            }
        }catch{
            if($_.Exception.Message -like 'Please wait *'){throw}
        }
    }
    if(-not $state.SocksPort -or [int]$state.SocksPort -lt 1 -or [int]$state.SocksPort -gt 65535){throw 'Session SOCKS port is unavailable; reconnect using H5.'}
    $socksPort=[int]$state.SocksPort
    $prior=$null
    try{$prior=Get-TTTorCheckViaSocks -SocksPort $socksPort}catch{}
    $priorIp=if($prior){[string]$prior.IP}else{''}

    $tcp=New-Object Net.Sockets.TcpClient
    $stream=$null;$reader=$null;$writer=$null
    try{
        $connect=$tcp.ConnectAsync('127.0.0.1',$port)
        if(-not $connect.Wait(3500) -or -not $tcp.Connected){throw 'Tor control listener did not accept the connection.'}
        $stream=$tcp.GetStream();$stream.ReadTimeout=5000;$stream.WriteTimeout=5000
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::ASCII)
        $writer=[IO.StreamWriter]::new($stream,[Text.Encoding]::ASCII)
        $writer.AutoFlush=$true
        $info=Invoke-TTControlCommand $writer $reader 'PROTOCOLINFO 1'
        Assert-TTControlResponse $info 'PROTOCOLINFO'
        $authLine=@($info|Where-Object{$_ -match '^250-AUTH '})|Select-Object -First 1
        if(-not $authLine -or $authLine -notmatch 'METHODS=(?:[^\s]*,)?SAFECOOKIE(?:,|\s|$)'){
            throw 'Tor did not offer SAFECOOKIE authentication.'
        }
        if($authLine -notmatch 'COOKIEFILE="((?:\\.|[^"\\])*)"'){
            throw 'Tor did not identify an authentication cookie.'
        }
        $reportedCookie=$matches[1].Replace('\\','\')
        if(-not [string]::Equals([IO.Path]::GetFullPath($reportedCookie),$expectedCookieFile,[StringComparison]::OrdinalIgnoreCase)){
            throw 'Tor reported an unexpected cookie path.'
        }
        $cookie=[IO.File]::ReadAllBytes($expectedCookieFile)
        if($cookie.Length -ne 32){throw 'Tor authentication cookie size was invalid.'}
        $nonce=New-Object byte[] 32
        $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
        try{$rng.GetBytes($nonce)}finally{$rng.Dispose()}
        $challenge=Invoke-TTControlCommand $writer $reader ('AUTHCHALLENGE SAFECOOKIE '+(Convert-TTHex $nonce))
        if(@($challenge).Count -lt 1 -or $challenge[-1] -notmatch '^250 AUTHCHALLENGE SERVERHASH=([0-9a-fA-F]{64}) SERVERNONCE=([0-9a-fA-F]{64})$'){
            throw 'Tor SAFECOOKIE challenge was rejected or malformed.'
        }
        $serverHash=ConvertFrom-TTHex $matches[1];$serverNonce=ConvertFrom-TTHex $matches[2]
        $expectedHash=Get-TTSafeCookieHmac 'Tor safe cookie authentication server-to-controller hash' $cookie $nonce $serverNonce
        if(-not (Test-TTBytesMatch $expectedHash $serverHash)){
            throw 'Tor SAFECOOKIE server verification failed. No signal was sent.'
        }
        $clientHash=Get-TTSafeCookieHmac 'Tor safe cookie authentication controller-to-server hash' $cookie $nonce $serverNonce
        $auth=Invoke-TTControlCommand $writer $reader ('AUTHENTICATE '+(Convert-TTHex $clientHash))
        Assert-TTControlResponse $auth 'AUTHENTICATE'
        $reply=Invoke-TTControlCommand $writer $reader 'SIGNAL NEWNYM'
        Assert-TTControlResponse $reply 'NEWNYM'
    }finally{
        if($writer){$writer.Dispose()}
        if($reader){$reader.Dispose()}
        if($stream){$stream.Dispose()}
        $tcp.Dispose()
    }
    # Tor may acknowledge NEWNYM without switching immediately; record only the request.
    $dir=Split-Path -Parent $cooldownFile
    if(-not(Test-Path -LiteralPath $dir)){New-Item -Path $dir -ItemType Directory -Force | Out-Null}
    $stamp=[datetime]::UtcNow.ToString('o')
    $cooldown=[ordered]@{format=1;sessionStarted=[string]$state.StartedAt;requestedUtc=$stamp}
    try{
        [IO.File]::WriteAllText($cooldownFile,($cooldown|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    }catch{Write-Warning 'Could not save the local circuit-request cooldown; Tor may still apply its own rate limit.'}
    Write-Host 'CIRCUIT REQUEST : ACKNOWLEDGED'
    Write-Host 'Tor control     : localhost / SAFECOOKIE authenticated'
    Write-Host 'Mode            : new connections only; existing streams remain intact'
    Write-Host ('Previous exit IP: '+$(if($priorIp){$priorIp}else{'not verified'}))
    Start-Sleep -Seconds 2
    $after=$null
    try{$after=Get-TTTorCheckViaSocks -SocksPort $socksPort}catch{}
    if($after){
        Write-Host ('Fresh exit IP   : '+[string]$after.IP)
        if($priorIp){Write-Host ('Exit IP changed : '+$(if($priorIp -ne [string]$after.IP){'YES'}else{'NO'}))}
        else{Write-Host 'Exit IP changed : NOT VERIFIED (no prior probe)'}
    }else{
        Write-Host 'Fresh exit IP   : unverified (Tor SOCKS probe unavailable)'
        Write-Host 'Exit IP changed : NOT VERIFIED'
    }
    Write-Host 'Note            : Tor may rate-limit NEWNYM or reuse the same US exit. Existing connections keep their circuits.'
    Write-Host 'Result: 0 | Network settings unchanged'
    exit 0
}catch{
    [Console]::Error.WriteLine('CIRCUIT REQUEST FAILED: '+$_.Exception.Message)
    exit 1
}
