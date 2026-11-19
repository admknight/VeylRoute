# TorTunnel Universal v2.0 GUI worker. Windows PowerShell 5.1, elevated from the VBS launcher.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Start','Stop','Preflight','Status','Health','Recover','Updates','Tidy','Untidy','UpdatePrepare','UpdateInstall','UpdateRollback','Inventory','ProvisionHelpers','ImportComponents','ExitAvailability','NewCircuit')][string]$Action,
  [Parameter(Mandatory=$true)][string]$Root,
  [Parameter(Mandatory=$true)][string]$LogPath,
  [ValidateSet('SystemWide','SelectedAppsOnly')][string]$RoutingMode='SystemWide',
  [string]$SourceDirectory='',
  [string]$CancelFile=''
)
$ErrorActionPreference='Stop'
$rootPath=[IO.Path]::GetFullPath($Root)
$internal=Join-Path $rootPath '_internal'
$guiInternal=Join-Path $internal 'gui'
$logDir=Split-Path -Parent $LogPath
if(-not(Test-Path -LiteralPath $logDir)){New-Item -Path $logDir -ItemType Directory -Force|Out-Null}
$reportFile=Join-Path $logDir 'last-result.json'
$utf8=New-Object Text.UTF8Encoding($false)
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$code=1;$recovery='Not needed';$details='';$taskStartedUtc=[datetime]::UtcNow
# No shell interpolation: quote input paths and reject embedded quote characters.
foreach($p in @($rootPath,$LogPath,$SourceDirectory,$CancelFile)){if($p -and $p.Contains('"')){throw 'File paths containing quotation marks are not supported.'}}
$engineScript=switch($Action){
  'Start' {Join-Path $internal 'Start-TorTunnel.ps1'}
  'Stop' {Join-Path $internal 'Stop-TorTunnel.ps1'}
  'Recover' {Join-Path $internal 'Stop-TorTunnel.ps1'}
  'Preflight' {Join-Path $internal 'Check-TorTunnel.ps1'}
  'Status' {Join-Path $internal 'Status-TorTunnel.ps1'}
  'Health' {Join-Path $internal 'Status-TorTunnel.ps1'}
  'Updates' {Join-Path $guiInternal 'TorTunnel.VersionCheck.ps1'}
  'ExitAvailability' {Join-Path $guiInternal 'TorTunnel.ExitAvailability.ps1'}
  'NewCircuit' {Join-Path $internal 'NewCircuit-TorTunnel.ps1'}
  'Tidy' {Join-Path $guiInternal 'TorTunnel.Maintenance.ps1'}
  'Untidy' {Join-Path $guiInternal 'TorTunnel.Maintenance.ps1'}
  'UpdatePrepare' {Join-Path $guiInternal 'TorTunnel.PackageUpdater.ps1'}
  'UpdateInstall' {Join-Path $guiInternal 'TorTunnel.PackageUpdater.ps1'}
  'UpdateRollback' {Join-Path $guiInternal 'TorTunnel.PackageUpdater.ps1'}
  default {Join-Path $guiInternal 'TorTunnel.BinarySetup.ps1'}
}
# Read child output without demanding exclusive access to Start-Process redirection.
# Windows may keep the redirected file open briefly after the child exits.
# A bounded retry handles this race without suppressing actual Start failures.
function Read-TTWorkerOutput([string]$Path,[int]$Attempts=25) {
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
  $lastError=''
  for($attempt=1;$attempt -le $Attempts;$attempt++){
    $stream=$null;$reader=$null
    try{
      $share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
      $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)
      $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
      return $reader.ReadToEnd()
    }catch [IO.IOException]{
      $lastError=$_.Exception.Message
    }catch [System.UnauthorizedAccessException]{
      $lastError=$_.Exception.Message
    }finally{
      if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}
    }
    if($attempt -lt $Attempts){Start-Sleep -Milliseconds 160}
  }
  throw ("Output log could not be read after $Attempts attempts: $Path. Last error: $lastError")
}
function Get-ChildFailure([string]$StdErrText,[string]$StdOutText,[int]$ExitCode){
  $message=if($StdErrText){$StdErrText.Trim()}else{''}
  if(-not $message -and $StdOutText){
    $match=[regex]::Match($StdOutText,'(?im)^\s*(?:ERROR:|START FAILED:|EXIT AVAILABILITY FAILED:|Worker error:|Exception:|Cannot |Failed |Download failed:)[^\r\n]*')
    if($match.Success){$message=$match.Value.Trim()}
  }
  if(-not $message){$message="Component process exited with code $ExitCode before it provided a diagnostic. The PowerShell child may have failed to initialize."}
  if($message.Length -gt 1800){$message=$message.Substring(0,1800)+'...'}
  return $message
}
function Invoke-Hidden([string]$Script,[string]$ChildArguments,[string]$Out,[string]$Err){
  if(-not(Test-Path -LiteralPath $Script -PathType Leaf)){throw "Missing worker target: $Script"}
  # All child -Action values must survive PowerShell parameter binding. $args is reserved.
  if(($Script -eq (Join-Path $guiInternal 'TorTunnel.BinarySetup.ps1') -or
      $Script -eq (Join-Path $guiInternal 'TorTunnel.PackageUpdater.ps1') -or
      $Script -eq (Join-Path $guiInternal 'TorTunnel.Maintenance.ps1')) -and
      $ChildArguments -notmatch '(?i)(^|\s)-Action\s+\S+'){
      throw "Worker dispatch error: missing required -Action for $Action. No child was launched."
  }
  $command='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$Script+'" -Root "'+$rootPath+'" '+$ChildArguments
  $proc=Start-Process -FilePath $ps -ArgumentList $command -WorkingDirectory $rootPath -WindowStyle Hidden -PassThru -RedirectStandardOutput $Out -RedirectStandardError $Err
  try{
    $proc.WaitForExit()
    return [int]$proc.ExitCode
  }finally{
    $proc.Dispose()
  }
  # Standard error is merged into the final activity log after the child completes.
  # Do not append to .out here: Start-Process or the GUI may still hold that file.
}
try{
  [IO.File]::WriteAllText($LogPath,"[$(Get-Date -Format o)] $Action - $rootPath`r`n",$utf8)
  $childArguments=switch($Action){
    'Start' { '-RoutingMode '+$RoutingMode+$(if($CancelFile){' -CancelFile "'+$CancelFile+'"'}else{''}) }
    'Stop' {'-NoPause'}
    'Recover' {'-NoPause -Recovery'}
    'Updates' {'-OutputPath "'+(Join-Path $rootPath 'runtime\gui\versions.json')+'"'}
    'ExitAvailability' {''}
    'Tidy' {'-Action Tidy'}
    'Untidy' {'-Action Untidy'}
    'UpdatePrepare' {if($SourceDirectory){'-Action Prepare -SourceDirectory "'+$SourceDirectory+'"'}else{'-Action Prepare'}}
    'UpdateInstall' {'-Action Install'}
    'UpdateRollback' {'-Action Rollback'}
    'Inventory' {'-Action Inventory'}
    'ProvisionHelpers' {'-Action DownloadHelpers'}
    'ImportComponents' {'-Action ImportFolder -SourceDirectory "'+$SourceDirectory+'"'}
    default {''}
  }
  $rawOut=$LogPath+'.out';$rawErr=$LogPath+'.err'
  $code=Invoke-Hidden -Script $engineScript -ChildArguments $childArguments -Out $rawOut -Err $rawErr
  $standardOutput=Read-TTWorkerOutput -Path $rawOut
  $standardError=Read-TTWorkerOutput -Path $rawErr
  # Do not trust a zero host exit code if stderr or the engine reports a failure.
  if($code -eq 0 -and -not [string]::IsNullOrWhiteSpace($standardError)){$code=35}
  # A PowerShell host can exit zero without actually acknowledging a control signal.
  if($code -eq 0 -and $Action -eq 'NewCircuit' -and
     $standardOutput -notmatch '(?im)^\s*CIRCUIT REQUEST\s*:\s*ACKNOWLEDGED\s*$'){
      $code=36;$details='Tor did not acknowledge a NEWNYM control request. Session networking was not changed by this operation.'
  }
  if($code -eq 0 -and $Action -eq 'Start' -and
     [regex]::IsMatch($standardOutput,'(?im)^\s*START FAILED:')){$code=34}
  if($code -ne 0 -and $code -ne 36){$details=Get-ChildFailure $standardError $standardOutput $code}
  if($code -eq 0 -and $Action -eq 'ProvisionHelpers'){
    $tun=Join-Path $rootPath 'tun2socks\tun2socks.exe'
    $win=Join-Path $rootPath 'tun2socks\wintun.dll'
    $receipt=Join-Path $rootPath 'runtime\component-setup\helpers-install.json'
    $valid=$false
    try {
        if((Test-Path -LiteralPath $tun -PathType Leaf) -and (Test-Path -LiteralPath $win -PathType Leaf) -and
           (Test-Path -LiteralPath $receipt -PathType Leaf)){
            $r=Get-Content -LiteralPath $receipt -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $stamp=([datetime]::Parse([string]$r.installedAt)).ToUniversalTime()
            $valid=($stamp -ge $taskStartedUtc.AddSeconds(-3) -and
                (Get-FileHash -LiteralPath $tun -Algorithm SHA256).Hash -eq [string]$r.tun2socksSha256 -and
                (Get-FileHash -LiteralPath $win -Algorithm SHA256).Hash -eq [string]$r.wintunSha256)
        }
    }catch{}
    if(-not $valid){$code=31;$details='Helper operation exited without a fresh install receipt and matching Wintun/tun2socks files at the portable target. No successful installation can be confirmed.'}
  }
  if($code -eq 0 -and $Action -eq 'UpdatePrepare'){
    $candidate=Join-Path $rootPath 'runtime\component-updates\verified-expert-bundle.json'
    $freshVerified=$false
    try {
      if(Test-Path -LiteralPath $candidate -PathType Leaf){
        $c=Get-Content -LiteralPath $candidate -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $stamp=([datetime]::Parse([string]$c.verifiedAt)).ToUniversalTime()
        $pkg=[string]$c.package
        $signature=[string]$c.signature
        $freshVerified=([string]$c.status -eq 'Verified' -and $stamp -ge $taskStartedUtc.AddSeconds(-3) -and
            (Test-Path -LiteralPath $pkg -PathType Leaf) -and
            (Test-Path -LiteralPath $signature -PathType Leaf) -and
            (Get-FileHash -LiteralPath $pkg -Algorithm SHA256).Hash -eq [string]$c.sha256)
      }
    }catch{}
    if(-not $freshVerified){$code=32;$details='Tor preparation did not create a fresh verified candidate with matching archive hash and detached signature. Existing older records are not proof of this attempt.'}
  }
  if($code -eq 0 -and $Action -eq 'UpdateInstall'){
    $installedRecord=Join-Path $rootPath 'runtime\component-updates\installed-expert-bundle.json'
    $installedExe=Join-Path $rootPath 'Tor\tor\tor.exe'
    $installedValid=$false
    try {
      if((Test-Path -LiteralPath $installedRecord -PathType Leaf) -and (Test-Path -LiteralPath $installedExe -PathType Leaf)){
        $r=Get-Content -LiteralPath $installedRecord -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $stamp=([datetime]::Parse([string]$r.installedAt)).ToUniversalTime()
        $installedValid=($stamp -ge $taskStartedUtc.AddSeconds(-3) -and
            [string]$r.installedVersion -match '^\d+\.\d+\.\d+\.\d+$' -and
            [string]$r.activeDirectory -eq (Join-Path $rootPath 'Tor'))
      }
    }catch{}
    if(-not $installedValid){$code=36;$details='Tor installation returned without a fresh installed-bundle receipt and matching Tor executable at the portable destination. Installation cannot be confirmed.'}
  }
  if($code -eq 0 -and $Action -eq 'ExitAvailability'){
    $cache=Join-Path $rootPath 'runtime\gui\exit-availability.json'
    $valid=$false
    try{
      if(Test-Path -LiteralPath $cache -PathType Leaf){
        $rec=Get-Content -LiteralPath $cache -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $fetched=([datetime]::Parse([string]$rec.fetchedAtUtc)).ToUniversalTime()
        $valid=([int]$rec.format -eq 1 -and [int]$rec.totalRunningExits -gt 0 -and
                $fetched -ge $taskStartedUtc.AddSeconds(-3) -and
                [string]$rec.source -eq 'Tor Project Onionoo running relays with Exit flag')
      }
    }catch{}
    if(-not $valid){$code=38;$details='The exit-relay lookup returned no fresh, verifiable data receipt. Country availability remains unverified.'}
  }
  if(-not [string]::IsNullOrEmpty($standardOutput)){
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value $standardOutput
  }
  if(-not [string]::IsNullOrEmpty($standardError)){
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ("`r`n-- Standard error --`r`n"+$standardError)
  }
  if($details){Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ('Verification error: '+$details)}
  if($Action -eq 'Start' -and $code -ne 0){
    if(Test-Path -LiteralPath (Join-Path $rootPath 'runtime\session-state.json')){
      $rc=Invoke-Hidden -Script (Join-Path $internal 'Stop-TorTunnel.ps1') -ChildArguments '-NoPause -Recovery' -Out ($LogPath+'.rollback') -Err ($LogPath+'.rollback.err')
      $recovery=if($rc -eq 0 -and -not(Test-Path -LiteralPath (Join-Path $rootPath 'runtime\session-state.json'))){'Rollback succeeded'}else{'INCOMPLETE - state retained'}
      Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ("`r`n-- START FAILURE RECOVERY -- $recovery")
      if(Test-Path -LiteralPath ($LogPath+'.rollback')){Get-Content -LiteralPath ($LogPath+'.rollback') | Add-Content -LiteralPath $LogPath -Encoding UTF8}
    }else{$recovery='Start failed without saved session state'}
  }
  Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "`r`nResult: $code | Recovery: $recovery"
}catch{
  $code=1;$details=$_.Exception.Message
  if($Action -eq 'Start' -and (Test-Path -LiteralPath (Join-Path $rootPath 'runtime\session-state.json'))){
    # A child may have established a healthy session before a log-read failure.
    # Preserve state for the engine's supported Status/Disconnect rather than
    # deleting or force-killing the connection in the GUI worker.
    $recovery='Unverified session retained; check Status/Health, then Disconnect if needed'
  }
  try{
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "Worker error: $details"
    Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value "Result: $code | Recovery: $recovery"
  }catch{}
}finally{
  if($Action -in @('ProvisionHelpers','ImportComponents','UpdatePrepare','UpdateInstall','UpdateRollback')){
    $progressPath=Join-Path $rootPath 'runtime\gui\component-progress.json'
    $fresh=$false;$state='';$stage=''
    try{
      if(Test-Path -LiteralPath $progressPath -PathType Leaf){
        $p=Get-Content -LiteralPath $progressPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $state=[string]$p.state;$stage=[string]$p.stage
        $fresh=([string]$p.action -eq $Action -and
          ([datetime]::Parse([string]$p.updatedUtc)).ToUniversalTime() -ge $taskStartedUtc.AddSeconds(-3))
      }
    }catch{}
    if($code -eq 0 -and (-not $fresh -or $state -ne 'Completed')){
      $code=33
      $details='No fresh completed component report was produced; installation not confirmed. The target files and signatures must be checked before use.'
    }
    if($code -ne 0 -and (-not $fresh -or $state -ne 'Failed')){
      try{
        $message=if($details){$details}else{'Background component worker failed. See optional technical details for the original exception.'}
        $failure=[ordered]@{format=1;action=$Action;state='Failed';stage=if($fresh -and $stage){$stage}else{'Component setup stopped before download'};
          percent=0;bytes=0;total=-1;destination='';detail=$message;updatedUtc=([datetime]::UtcNow.ToString('o'))}
        $tmp=$progressPath+'.tmp-'+[guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllText($tmp,(($failure|ConvertTo-Json -Depth 5)+"`r`n"),$utf8)
        $backup=$progressPath+'.bak-'+[guid]::NewGuid().ToString('N')
        try{
          if(Test-Path -LiteralPath $progressPath -PathType Leaf){[IO.File]::Replace($tmp,$progressPath,$backup)}
          else{[IO.File]::Move($tmp,$progressPath)}
        }finally{
          if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
          if(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue}
        }
      }catch{try{Add-Content -LiteralPath $LogPath -Encoding UTF8 -Value ('Progress recording error: '+$_.Exception.Message)}catch{}}
    }
  }
  $result=[ordered]@{action=$Action;exitCode=$code;recovery=$recovery;detail=$details;finishedAt=(Get-Date).ToString('o');logPath=$LogPath}
  try{[IO.File]::WriteAllText($reportFile,($result|ConvertTo-Json -Depth 5),$utf8)}catch{}
}
exit $code
