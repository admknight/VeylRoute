[CmdletBinding()]
param([switch]$PauseAtEnd, [string]$Root)
$ErrorActionPreference = 'Stop'
$InternalRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = [IO.Path]::GetFullPath((Split-Path -Parent $InternalRoot))
} else {
    $Root = [IO.Path]::GetFullPath($Root.TrimEnd('\'))
}
$ListPath = Join-Path $Root 'config\tor-apps.txt'
try {
    if (-not (Test-Path -LiteralPath $ListPath)) {
        Write-Host 'No tor-apps.txt exists; there are no TOR-only apps.' -ForegroundColor Yellow
        if ($PauseAtEnd) { [void](Read-Host 'Press Enter to close') }; exit 0
    }
    $lines = @(Get-Content -LiteralPath $ListPath)
    $entries = @()
    for ($i=0; $i -lt $lines.Count; $i++) {
        $t=[string]$lines[$i]; if (-not $t) { continue }
        $trim=$t.Trim(); if (-not $trim -or $trim.StartsWith('#')) { continue }
        $entries += [pscustomobject]@{LineIndex=$i;Text=$t;Display=$trim.Trim('"')}
    }
    if ($entries.Count -eq 0) {
        Write-Host 'There are no TOR-only applications configured.' -ForegroundColor Yellow
        if ($PauseAtEnd) { [void](Read-Host 'Press Enter to close') }; exit 0
    }
    Write-Host ''; Write-Host 'TOR-only applications:' -ForegroundColor Cyan
    for ($i=0; $i -lt $entries.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i+1),$entries[$i].Display) }
    Write-Host '  [A] Remove ALL'; Write-Host '  [Q] Cancel'
    $answer=(Read-Host 'Choose an item').Trim(); if ($answer -ieq 'q') { exit 0 }
    if ($answer -ieq 'a') { $removeIndexes=@($entries|ForEach-Object{$_.LineIndex}) }
    elseif ($answer -match '^\d+$' -and [int]$answer -ge 1 -and [int]$answer -le $entries.Count) { $removeIndexes=@($entries[[int]$answer-1].LineIndex) }
    else { throw 'Invalid selection.' }
    $kept=for($i=0;$i -lt $lines.Count;$i++){if($removeIndexes -notcontains $i){$lines[$i]}}
    Set-Content -LiteralPath $ListPath -Value $kept -Encoding UTF8
    Write-Host 'TOR-only app list updated.' -ForegroundColor Green
    if (Test-Path -LiteralPath (Join-Path $Root 'runtime\session-state.json')) { Write-Warning 'List changes require Stop, then Start again.' }
}
catch { Write-Host "Could not remove TOR app: $($_.Exception.Message)" -ForegroundColor Red; if($PauseAtEnd){[void](Read-Host 'Press Enter to close')}; exit 1 }
if($PauseAtEnd){[void](Read-Host 'Press Enter to close')}
