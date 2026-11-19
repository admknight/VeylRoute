# TorTunnel Universal Control Center v2.0: read-only component inventory and official Tor release check.
# Windows PowerShell 5.1. No downloads of executables and no file replacement.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
$rootPath = [IO.Path]::GetFullPath($Root)
$utf8 = New-Object System.Text.UTF8Encoding($false)
$report = [ordered]@{
    checkedAt = (Get-Date).ToString('o')
    source = 'https://download.torproject.org/tor/ (core); https://dist.torproject.org/torbrowser/ (Windows bundle)'
    installedTor = $null
    torExecutable = $null
    latestCore = $null
    latestWindowsExpertCore = $null
    latestWindowsExpertRelease = $null
    updateAvailable = $null
    checkState = 'Unknown'
    details = ''
    components = @()
}
function Add-Component([string]$Name,[string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    $v = if ($info.ProductVersion) { [string]$info.ProductVersion } elseif ($info.FileVersion) { [string]$info.FileVersion } else { 'Not embedded in file' }
    $script:report.components += [ordered]@{ name=$Name; version=$v; file=$Path }
}
function Get-TorVersion([string]$Path) {
    $p = New-Object Diagnostics.Process
    $p.StartInfo = New-Object Diagnostics.ProcessStartInfo
    $p.StartInfo.FileName = $Path
    $p.StartInfo.Arguments = '--version'
    $p.StartInfo.WorkingDirectory = [IO.Path]::GetDirectoryName($Path)
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.RedirectStandardOutput = $true
    $p.StartInfo.RedirectStandardError = $true
    $p.StartInfo.CreateNoWindow = $true
    try {
        if (-not $p.Start()) { throw 'Cannot start Tor version probe.' }
        if (-not $p.WaitForExit(8000)) {
            try { $p.Kill() } catch {}
            throw 'Tor version probe timed out.'
        }
        $output = $p.StandardOutput.ReadToEnd() + "`n" + $p.StandardError.ReadToEnd()
        if ($output -match '(?i)\bTor(?:\s+version)?\s+v?(\d+\.\d+\.\d+\.\d+)\b') { return $Matches[1] }
        throw 'Tor did not return a recognizable version.'
    }
    finally { $p.Dispose() }
}
try {
    $torFolder = Join-Path $rootPath 'Tor'
    $candidates = @((Join-Path $torFolder 'tor\tor.exe'),(Join-Path $torFolder 'tor.exe'))
    $tor = $null
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c -PathType Leaf) { $tor = $c; break } }
    if (-not $tor -and (Test-Path -LiteralPath $torFolder -PathType Container)) {
        $found = Get-ChildItem -LiteralPath $torFolder -Filter 'tor.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $tor = $found.FullName }
    }
    if ($tor) {
        $report.torExecutable = $tor
        try { $report.installedTor = Get-TorVersion $tor }
        catch { $report.details = 'Local version check failed: ' + $_.Exception.Message }
        Add-Component 'Tor executable (file metadata)' $tor
    }
    else { $report.details = 'Tor executable not found under the Tor folder.' }
    $lyrebird = if (Test-Path -LiteralPath $torFolder -PathType Container) { Get-ChildItem -LiteralPath $torFolder -Filter 'lyrebird.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
    if ($lyrebird) { Add-Component 'lyrebird (file metadata)' $lyrebird.FullName }
    Add-Component 'tun2socks (file metadata)' (Join-Path $rootPath 'tun2socks\tun2socks.exe')
    Add-Component 'Wintun (file metadata)' (Join-Path $rootPath 'tun2socks\wintun.dll')
    # The official page distinguishes core Tor releases from Windows Expert Bundle binaries.
    # A newer core source version does not imply a corresponding Windows bundle is available.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $page = Invoke-WebRequest -Uri 'https://download.torproject.org/tor/' -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        if ([int]$page.StatusCode -ne 200) { throw 'Official Tor release page returned a non-200 HTTP status.' }
        $responseHost = ([Uri]$page.BaseResponse.ResponseUri).Host
        if ($responseHost -notmatch '(^|\.)torproject\.org$') { throw "Unexpected update source host: $responseHost" }
        $markup = [string]$page.Content
        $plain = [Net.WebUtility]::HtmlDecode([regex]::Replace($markup,'<[^>]+>',' '))
        $plain = [regex]::Replace($plain,'\s+',' ')
        $coreMatch = [regex]::Match($plain, '(?i)Little-t\s+tor.{0,1000}?\bTor\s+(\d+\.\d+\.\d+\.\d+)\b')
        if (-not $coreMatch.Success) { throw 'Could not confidently identify the stable core Tor version on the official release page.' }
        $report.latestCore = [string]$coreMatch.Groups[1].Value
        $bundleMatch = [regex]::Match($plain,'(?i)tor expert bundle.{0,2500}?\(tor\s+(\d+\.\d+\.\d+\.\d+)\)\s+Stable')
        if ($bundleMatch.Success) { $report.latestWindowsExpertCore = [string]$bundleMatch.Groups[1].Value }
        if ($report.installedTor) {
            $report.updateAvailable = ([version]$report.latestCore -gt [version]$report.installedTor)
            $report.checkState = if ($report.updateAvailable) { 'UpdateAvailable' } else { 'UpToDate' }
        }
        else { $report.checkState = 'LocalVersionUnknown' }
    }
    catch {
        $report.checkState = 'UnableToVerify'
        $report.details = ($report.details + ' Official version check: ' + $_.Exception.Message).Trim()
    }
    # Independent official distribution check. Bundle release is NOT the core Tor version.
    try {
        $dist='https://dist.torproject.org/torbrowser/'
        $idx=Invoke-WebRequest -Uri $dist -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        if(([uri]$idx.BaseResponse.ResponseUri).Host -ne 'dist.torproject.org'){throw 'Unexpected distribution host.'}
        $matches=@([regex]::Matches([string]$idx.Content,'(?i)href\s*=\s*["\x27](?<v>\d+\.\d+(?:\.\d+)?)/["\x27]'))
        $versions=@($matches | ForEach-Object {$_.Groups['v'].Value} | Sort-Object -Unique | Sort-Object -Property {[version]$_} -Descending)
        foreach($tag in ($versions | Select-Object -First 12)){
            try {
                $listing=Invoke-WebRequest -Uri ($dist+$tag+'/') -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
                if(([uri]$listing.BaseResponse.ResponseUri).Host -ne 'dist.torproject.org'){continue}
                $name='tor-expert-bundle-windows-x86_64-'+$tag+'.tar.gz'
                if([string]$listing.Content -match [regex]::Escape($name+'.asc') -and
                   [string]$listing.Content -match [regex]::Escape($name)){
                    $report.latestWindowsExpertRelease=$tag
                    break
                }
            } catch {}
        }
        if(-not $report.latestWindowsExpertRelease){throw 'No signed Windows Expert Bundle in the currently indexed stable releases.'}
        if($report.checkState -eq 'UnableToVerify'){
            $report.details=($report.details+' Independent official distribution listing succeeded; core Tor version still unverified.').Trim()
        }
    } catch {
        $report.details=($report.details+' Distribution source: '+$_.Exception.Message).Trim()
    }

    $report | ConvertTo-Json -Depth 10 | ForEach-Object { [IO.File]::WriteAllText($OutputPath, $_ + "`r`n", $utf8) }
    Write-Output ('Installed Tor: ' + $(if ($report.installedTor) { $report.installedTor } else { 'unknown' }))
    Write-Output ('Latest core Tor: ' + $(if ($report.latestCore) { $report.latestCore } else { 'unavailable' }))
    Write-Output ('Latest Windows Expert Bundle Tor: ' + $(if ($report.latestWindowsExpertCore) { $report.latestWindowsExpertCore } else { 'not verified' }))
    Write-Output ('Update status: ' + $report.checkState)
    Write-Output 'No binaries were downloaded, installed or modified.'
    if ($report.details) { Write-Output ('Notes: ' + $report.details) }
}
catch {
    Write-Error ('Version inventory failed: ' + $_.Exception.Message)
    exit 1
}
