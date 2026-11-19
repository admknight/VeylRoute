# VeylRoute Control Center v3.0 Windows RC1 (TorTunnel Universal engine v3.5.1)
# WPF/XAML controller for TorTunnel Universal v3.5.1; never implements network routing itself.
# Windows PowerShell 5.1 / STA. Launch using VeylRoute.vbs.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Root = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:ConfigDir = Join-Path $script:Root 'config'
$script:ConfigPath = Join-Path $script:ConfigDir 'settings.json'
$script:PrefsPath = Join-Path $script:ConfigDir 'gui-settings.json'
$script:SetupGuideFlagPath = Join-Path $script:ConfigDir 'veylroute-setup-guide.json'
$script:BridgesPath = Join-Path $script:ConfigDir 'bridges.txt'
$script:AppsPath = Join-Path $script:ConfigDir 'excluded-apps.txt'
$script:TorAppsPath = Join-Path $script:ConfigDir 'tor-apps.txt'
$script:PendingImportDirectory = ''
$script:StatePath = Join-Path $script:Root 'runtime\session-state.json'
$script:WorkerPath = Join-Path $script:Root '_internal\gui\TorTunnel.GuiWorker.ps1'
$script:LogDir = Join-Path $script:Root 'runtime\gui'
$script:VersionsPath = Join-Path $script:LogDir 'versions.json'
$script:StatusCachePath = Join-Path $script:LogDir 'last-verified-status.json'
$script:VerifiedPackagePath = Join-Path $script:Root 'runtime\component-updates\verified-expert-bundle.json'
$script:PrepareStagePath = Join-Path $script:Root 'runtime\component-updates\last-prepare-result.json'
$script:TransferProgressPath = Join-Path $script:LogDir 'component-progress.json'
$script:ExitAvailabilityPath = Join-Path $script:LogDir 'exit-availability.json'
$script:ExitAvailability = $null
$script:CancelFile = ''
$script:CancelRequested = $false
$script:CurrentDisplayLog = ''
$script:LiveBootstrap = -1

$script:TransferStartedUtc = [datetime]::MinValue
$script:TransferVisibleAction = ''
$script:InstalledPackagePath = Join-Path $script:Root 'runtime\component-updates\installed-expert-bundle.json'
$script:TrayArt = @{}
$script:TrayCurrent = ''
$script:SessionKey = ''
$script:AutoStatusLastStart = [datetime]::MinValue
$script:AutoStatusInitialDue = [datetime]::MinValue
$script:AutoStatusEverySeconds = 180
$script:StatusCacheLoaded = $false
$script:PowerShellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:Window = $null
$script:Ui = @{}
$script:Selected = @{}
$script:CountryRows = @()
$script:CountryNames = @{}
$script:Settings = $null
$script:Prefs = $null
$script:BusyProc = $null
$script:BusyAction = ''
$script:LastLog = ''
$script:LastLogStamp = ''
$script:LastMessage = ''
$script:BusyAutomatic = $false
$script:PendingIssue = $null
$script:LastAutomaticIssueSignature = ''
$script:LastGuiInternalFault = ''
$script:UiReady = $false
$script:VerifiedThisSession = $false
$script:ExitRequested = $false
$script:SuppressDoh = $false
$script:SuppressCountry = $false
$script:LastPulse = 0
$script:PageName = 'Dashboard'
$script:TrayIcon = $null
$script:TrayMenu = $null
$script:TrayHintShown = $false
$script:LastReadinessSnapshot = $null
$script:Mutex = $null
$script:WakeEvent = $null
$script:Timer = $null
$script:DohPresets = @(
    [pscustomobject]@{ Name='Cloudflare'; Primary='1.1.1.1'; Secondary='1.0.0.1'; Endpoint='https://cloudflare-dns.com/dns-query' },
    [pscustomobject]@{ Name='Google Public DNS'; Primary='8.8.8.8'; Secondary='8.8.4.4'; Endpoint='https://dns.google/dns-query' },
    [pscustomobject]@{ Name='Quad9 Secure'; Primary='9.9.9.9'; Secondary='149.112.112.112'; Endpoint='https://dns.quad9.net/dns-query' },
    [pscustomobject]@{ Name='Cloudflare Malware'; Primary='1.1.1.2'; Secondary='1.0.0.2'; Endpoint='https://security.cloudflare-dns.com/dns-query' },
    [pscustomobject]@{ Name='AdGuard DNS (Ad blocking)'; Primary='94.140.14.14'; Secondary='94.140.15.15'; Endpoint='https://dns.adguard-dns.com/dns-query' },
    [pscustomobject]@{ Name='AdGuard DNS (Unfiltered)'; Primary='94.140.14.140'; Secondary='94.140.14.141'; Endpoint='https://unfiltered.adguard-dns.com/dns-query' },
    [pscustomobject]@{ Name='AdGuard DNS (Family)'; Primary='94.140.14.15'; Secondary='94.140.15.16'; Endpoint='https://family.adguard-dns.com/dns-query' },
    [pscustomobject]@{ Name='CleanBrowsing Security'; Primary='185.228.168.9'; Secondary='185.228.169.9'; Endpoint='https://doh.cleanbrowsing.org/doh/security-filter/' }
)

function Read-Text([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    return [IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
}
function Read-Json([string]$Path) {
    $text = Read-Text $Path
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json -ErrorAction Stop)
}
function Field($Object,[string]$Name,$Fallback) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name] -and $null -ne $Object.PSObject.Properties[$Name].Value) {
        return $Object.PSObject.Properties[$Name].Value
    }
    return $Fallback
}
function Set-Field($Object,[string]$Name,$Value) {
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    } else { $Object.PSObject.Properties[$Name].Value = $Value }
}
function Has-Session { return (Test-Path -LiteralPath $script:StatePath -PathType Leaf) }
function In-Progress { return ($null -ne $script:BusyProc -and -not $script:BusyProc.HasExited) }
# WPF-native dialog shell: no generic Windows MessageBox is used once the window loads.
# A confirmation defaults to NO if it cannot be displayed (fail safe).
# The same WPF dialog handles confirmations, notifications, actionable failures,
# and startup errors that occur before the main window is available.
function Show-TTDialog {
    param(
        [string]$Text,
        [string]$Title='VeylRoute',
        [bool]$Confirm=$false,
        [System.Windows.MessageBoxImage]$Icon=[System.Windows.MessageBoxImage]::Information,
        [string]$Solution='',
        [string]$ActionLabel='',
        [string]$ActionKey='',
        [string]$Details=''
    )
    $xaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="VeylRoute" Width="630" MinHeight="210" MaxHeight="730" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize" ShowInTaskbar="False"
        FontFamily="Segoe UI" FontSize="13">
  <Border Name="DialogShell" CornerRadius="18" BorderThickness="1" Padding="25">
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="7" Opacity="0.28"/></Border.Effect>
    <StackPanel>
      <DockPanel Name="DialogHeader" LastChildFill="True" Margin="0,0,0,17" Cursor="SizeAll">
        <Border Name="DialogBadge" Width="42" Height="42" CornerRadius="11" DockPanel.Dock="Left" Margin="0,0,13,0">
          <TextBlock Name="DialogGlyph" FontSize="23" FontWeight="SemiBold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Name="DialogTitle" FontSize="19" FontWeight="SemiBold" TextWrapping="Wrap" MaxWidth="490"/>
          <TextBlock Name="DialogCaption" FontSize="11" Margin="0,3,0,0"/>
        </StackPanel>
      </DockPanel>
      <TextBlock Name="DialogBody" TextWrapping="Wrap" LineHeight="21" MaxWidth="560" Margin="0,0,0,18"/>
      <Border Name="DialogGuidanceShell" Visibility="Collapsed" CornerRadius="11" Padding="15" Margin="0,0,0,16">
        <StackPanel>
          <TextBlock Name="DialogGuidanceTitle" Text="WHAT TO DO" FontWeight="SemiBold" FontSize="11" Margin="0,0,0,7"/>
          <TextBlock Name="DialogGuidance" TextWrapping="Wrap" LineHeight="20" MaxWidth="535"/>
        </StackPanel>
      </Border>
      <Expander Name="DialogDetails" Visibility="Collapsed" Header="Technical details (optional)" Margin="0,0,0,14">
        <TextBox Name="DialogDetailsText" Height="132" Margin="0,9,0,0" IsReadOnly="True"
                 TextWrapping="Wrap" FontFamily="Consolas" FontSize="11" Padding="9"
                 VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
      </Expander>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,3,0,0">
        <Button Name="DialogCancel" Content="Cancel" Height="40" MinWidth="90" Margin="0,0,8,0"/>
        <Button Name="DialogAction" Content="Open setup" Height="40" MinWidth="150" Margin="0,0,8,0" Visibility="Collapsed"/>
        <Button Name="DialogAccept" Content="Close" Height="40" MinWidth="102"/>
      </StackPanel>
    </StackPanel>
  </Border>
</Window>
'@
    try {
        $dlg=[System.Windows.Markup.XamlReader]::Parse($xaml)
        $hasOwner=($null -ne $script:Window -and $script:Window.IsVisible)
        if ($hasOwner) { $dlg.Owner=$script:Window; $dlg.WindowStartupLocation=[System.Windows.WindowStartupLocation]::CenterOwner }
        else { $dlg.Topmost=$true }
        $badgeFile=Join-Path $PSScriptRoot 'assets\VeylRoute-warning.ico'
        if (Test-Path -LiteralPath $badgeFile -PathType Leaf) {
            try { $dlg.Icon=[System.Windows.Media.Imaging.BitmapFrame]::Create(([Uri]::new($badgeFile,[UriKind]::Absolute))) } catch {}
        }
        $dark=($null -eq $script:Window -or $script:CurrentTheme -ne 'light')
        $surface=[System.Windows.Media.Brushes]::White
        $border=[System.Windows.Media.Brushes]::Gray
        $foreground=[System.Windows.Media.Brushes]::Black
        $muted=[System.Windows.Media.Brushes]::Gray
        $accent=[System.Windows.Media.Brushes]::Teal
        $accentText=[System.Windows.Media.Brushes]::White
        $warning=[System.Windows.Media.Brushes]::Orange
        $danger=[System.Windows.Media.Brushes]::Crimson
        $inputSurface=[System.Windows.Media.Brushes]::WhiteSmoke
        if ($script:Window) {
            $surface=$script:Window.Resources['TT.Surface']
            $border=$script:Window.Resources['TT.Border']
            $foreground=$script:Window.Resources['TT.Text']
            $muted=$script:Window.Resources['TT.Muted']
            $accent=$script:Window.Resources['TT.Accent']
            $accentText=$script:Window.Resources['TT.AccentText']
            $warning=$script:Window.Resources['TT.Warning']
            $danger=$script:Window.Resources['TT.Danger']
            $inputSurface=$script:Window.Resources['TT.SurfaceAlt']
        } elseif($dark) {
            $surface=([System.Windows.Media.BrushConverter]::new()).ConvertFromString('#142B48')
            $border=([System.Windows.Media.BrushConverter]::new()).ConvertFromString('#365576')
            $foreground=[System.Windows.Media.Brushes]::White
            $muted=[System.Windows.Media.Brushes]::LightGray
            $inputSurface=([System.Windows.Media.BrushConverter]::new()).ConvertFromString('#203C5A')
        }
        $dlg.FindName('DialogTitle').Text=$Title
        $dlg.FindName('DialogBody').Text=$Text
        $dlg.FindName('DialogShell').Background=$surface
        $dlg.FindName('DialogShell').BorderBrush=$border
        $dlg.FindName('DialogTitle').Foreground=$foreground
        $dlg.FindName('DialogBody').Foreground=$foreground
        $dlg.FindName('DialogCaption').Foreground=$muted
        $color=$accent; $glyph='i'; $caption='INFORMATION'
        if($Confirm){$color=$warning;$glyph='?';$caption='CONFIRM ACTION'}
        elseif($Icon -eq [System.Windows.MessageBoxImage]::Error){$color=$danger;$glyph='!';$caption='ACTION NEEDED'}
        elseif($Icon -eq [System.Windows.MessageBoxImage]::Warning){$color=$warning;$glyph='!';$caption='ATTENTION'}
        $dlg.FindName('DialogGlyph').Text=$glyph
        $dlg.FindName('DialogGlyph').Foreground=$accentText
        $dlg.FindName('DialogBadge').Background=$color
        $dlg.FindName('DialogCaption').Text=$caption
        if(-not [string]::IsNullOrWhiteSpace($Solution)){
            $dlg.FindName('DialogGuidanceShell').Visibility=[System.Windows.Visibility]::Visible
            $dlg.FindName('DialogGuidanceShell').Background=$inputSurface
            $dlg.FindName('DialogGuidanceTitle').Foreground=$accent
            $dlg.FindName('DialogGuidance').Foreground=$foreground
            $dlg.FindName('DialogGuidance').Text=$Solution
        }
        if(-not [string]::IsNullOrWhiteSpace($Details)){
            $exp=$dlg.FindName('DialogDetails')
            $exp.Visibility=[System.Windows.Visibility]::Visible
            $exp.Foreground=$muted
            $dt=$dlg.FindName('DialogDetailsText')
            $dt.Text=if($Details.Length -gt 4500){$Details.Substring(0,4500)+"`r`n[Additional diagnostics remain in Activity]"}else{$Details}
            $dt.Background=$inputSurface;$dt.Foreground=$foreground;$dt.BorderBrush=$border
        }
        $accept=$dlg.FindName('DialogAccept')
        $cancel=$dlg.FindName('DialogCancel')
        $action=$dlg.FindName('DialogAction')
        foreach($button in @($accept,$cancel,$action)){
            if($script:Window){$button.Style=$script:Window.Resources['BaseButton']}
            else{$button.Background=$inputSurface;$button.Foreground=$foreground;$button.BorderBrush=$border;$button.Padding=[System.Windows.Thickness]::new(15,0,15,0)}
        }
        if($Confirm){
            $accept.Content='Yes, continue'
            $cancel.Visibility=[System.Windows.Visibility]::Visible
            if($script:Window){$accept.Style=$script:Window.Resources['PrimaryButton']}
        } else {
            $accept.Content='Close'
            $cancel.Visibility=[System.Windows.Visibility]::Collapsed
        }
        if($ActionKey -and $ActionLabel -and -not $Confirm){
            $action.Visibility=[System.Windows.Visibility]::Visible
            $action.Content=$ActionLabel
            $action.Tag='__ACTION__'
            if($script:Window){$action.Style=$script:Window.Resources['PrimaryButton']}
            else{$action.Background=$accent;$action.Foreground=$accentText}
        }
        $dlg.FindName('DialogHeader').Add_MouseLeftButtonDown({
            param($sender,$eventArgs)
            try { $w=[System.Windows.Window]::GetWindow($sender);if($w){$w.DragMove()} }catch{}
        })
        $accept.Add_Click({param($sender,$eventArgs)
            $w=[System.Windows.Window]::GetWindow($sender)
            if($w){$w.DialogResult=$true}
        })
        $cancel.Add_Click({param($sender,$eventArgs)
            $w=[System.Windows.Window]::GetWindow($sender)
            if($w){$w.DialogResult=$false}
        })
        $action.Add_Click({param($sender,$eventArgs)
            $w=[System.Windows.Window]::GetWindow($sender)
            if($w){$w.Tag=[string]$sender.Tag;$w.DialogResult=$true}
        })
        $response=$dlg.ShowDialog()
        if($Confirm){return ($response -eq $true)}
        if($ActionKey){return ($response -eq $true -and [string]$dlg.Tag -eq '__ACTION__')}
        return $false
    }catch{
        try{
            if(-not(Test-Path -LiteralPath $script:LogDir)){New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null}
            Add-Content -LiteralPath (Join-Path $script:LogDir 'wpf-dialog-errors.log') -Value ((Get-Date -Format o)+' '+$Title+': '+$_.Exception.Message) -Encoding UTF8
        }catch{}
        try {Set-Footer ($Title+': '+$Text)}catch{}
        return $false
    }
}
function Notice([string]$Text,[string]$Title='VeylRoute',[System.Windows.MessageBoxImage]$Icon=[System.Windows.MessageBoxImage]::Information) {
    if($Icon -eq [System.Windows.MessageBoxImage]::Error -or $Icon -eq [System.Windows.MessageBoxImage]::Warning){
        $issue=Get-VeylIssue -Action $Title -Text $Text
        Present-VeylIssue $issue
    }else{[void](Show-TTDialog -Text $Text -Title $Title -Icon $Icon)}
}
function Ask([string]$Text,[string]$Title='VeylRoute') {
    return (Show-TTDialog -Text $Text -Title $Title -Confirm $true -Icon ([System.Windows.MessageBoxImage]::Warning))
}
function Assert-Editable {
    if (In-Progress) { throw 'An operation is already running. Finish it before saving settings.' }
    if (Has-Session) { throw 'Stop or recover VeylRoute before changing configuration. A session-state file is present.' }
}
function Is-IPv4([string]$Value) {
    $out = $null
    return ([Net.IPAddress]::TryParse($Value,[ref]$out) -and $out.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork)
}
function Parse-Integer([string]$Value,[int]$Minimum,[int]$Maximum,[string]$Label) {
    $result = 0
    if (-not [int]::TryParse($Value.Trim(),[ref]$result) -or $result -lt $Minimum -or $result -gt $Maximum) {
        throw "$Label must be a whole number between $Minimum and $Maximum."
    }
    return $result
}
function Set-Footer([string]$Text) {
    $script:LastMessage = $Text
    if ($script:UiReady) {
        $script:Ui.FooterText.Text = $Text
        $script:Ui.DashboardLastAction.Text = $Text
    }
}
function Convert-ToCRLF([string]$Text) {
    return (($Text -replace "`r`n", "`n") -replace "`r", "`n") -replace "`n", "`r`n"
}
function Get-ThemePreference {
    try {
        if ([System.Windows.SystemParameters]::HighContrast) { return 'contrast' }
        $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop
        if ($p.AppsUseLightTheme -eq 1) { return 'light' }
    } catch {}
    return 'dark'
}
function Apply-Theme([string]$Mode) {
    $dark = @{
        Background='#081322'; Sidebar='#0D2036'; Surface='#142B48'; SurfaceAlt='#203C5A'; Border='#365576';
        Text='#F5F9FF'; Muted='#B5CDE5'; Accent='#52D5F1'; AccentText='#071A2C'; Warning='#FFCA75'; Danger='#FF7690'; Glow='#17496A'; Hero='#12395A'; Highlight='#9674FF'; InputHover='#6BA2CA'; SelectChosen='#294B70'
    }
    $light = @{
        Background='#F3F7FE'; Sidebar='#FFFFFF'; Surface='#FFFFFF'; SurfaceAlt='#EBF3FC'; Border='#D5E1F1';
        Text='#102C48'; Muted='#526D89'; Accent='#087CAC'; AccentText='#FFFFFF'; Warning='#916012'; Danger='#B42A55'; Glow='#DEF3FF'; Hero='#E2F1FF'; Highlight='#614DCC'; InputHover='#3C94B7'; SelectChosen='#DBEFFC'
    }
    $colors = if ($Mode -eq 'light') { $light } else { $dark }
    if ($Mode -eq 'contrast') {
        $colors = @{
            Background=[string][System.Windows.SystemColors]::WindowColor; Sidebar=[string][System.Windows.SystemColors]::WindowColor;
            Surface=[string][System.Windows.SystemColors]::WindowColor; SurfaceAlt=[string][System.Windows.SystemColors]::ControlColor;
            Border=[string][System.Windows.SystemColors]::WindowTextColor; Text=[string][System.Windows.SystemColors]::WindowTextColor;
            Muted=[string][System.Windows.SystemColors]::WindowTextColor; Accent=[string][System.Windows.SystemColors]::HighlightColor;
            AccentText=[string][System.Windows.SystemColors]::HighlightTextColor; Warning='#D9A400'; Danger='#C94D4D'; Glow='#333333';
            Hero=[string][System.Windows.SystemColors]::WindowColor; Highlight=[string][System.Windows.SystemColors]::HighlightColor; InputHover=[string][System.Windows.SystemColors]::HighlightColor; SelectChosen=[string][System.Windows.SystemColors]::HighlightColor
        }
    }
    foreach ($key in $colors.Keys) {
        $resource = $script:Window.Resources['TT.' + $key]
        if ($resource -is [System.Windows.Media.SolidColorBrush]) {
            $color=[System.Windows.Media.ColorConverter]::ConvertFromString([string]$colors[$key])
            $script:Window.Resources['TT.' + $key] = [System.Windows.Media.SolidColorBrush]::new($color)
        }
    }
    $script:CurrentTheme = $Mode
    $script:Ui.LblTheme.Text = if ($Mode -eq 'dark') { 'Switch to light theme' } else { 'Switch to dark theme' }
    Set-NavActive $script:PageName
}
function Set-NavActive([string]$Name) {
    if (-not $script:UiReady) { return }
    foreach ($name in @('Dashboard','Countries','Dns','Apps','Bridges','Security','Updates','Activity','Maintenance')) {
        $button = $script:Ui['Nav' + $name]
        if ($Name -eq $name) {
            $button.Background = $script:Window.Resources['TT.Glow']
            $button.Foreground = $script:Window.Resources['TT.Accent']
            $button.FontWeight = [System.Windows.FontWeights]::SemiBold
        } else {
            $button.Background = $script:Window.Resources['TT.Sidebar']
            $button.Foreground = $script:Window.Resources['TT.Text']
            $button.FontWeight = [System.Windows.FontWeights]::Normal
        }
    }
}
function Show-Page([string]$Name) {
    if (-not $script:UiReady) { return }
    $titles = @{
        Dashboard=@('Overview','Connection and system health at a glance');
        Countries=@('Exit locations','Country restrictions and selection modes');
        Dns=@('DNS protection','Secure resolver settings');
        Apps=@('Application routing','DIRECT bypass and TOR-only application policies');
        Bridges=@('obfs4 bridges','Bridge configuration and validation');
        Security=@('Advanced settings','Protection controls and network tuning');
        Updates=@('Versions & updates','Signed Tor Expert Bundle updates and rollback');
        Activity=@('Activity log','Full diagnostic output from the existing engine');
        Maintenance=@('Maintenance','Reversible file-visibility and recovery controls')
    }
    if (-not $titles.ContainsKey($Name)) { return }
    foreach ($key in $titles.Keys) {
        $script:Ui['Page' + $key].Visibility = if ($key -eq $Name) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    }
    $script:PageName = $Name
    $script:Ui.HeaderTitle.Text = $titles[$Name][0]
    $script:Ui.HeaderSubtitle.Text = $titles[$Name][1]
    Set-NavActive $Name
    if($Name -in @('Updates','Bridges')){[void](Refresh-VeylComponentReadiness)}
}

# Read-only component readiness. File presence is NEVER treated as signature or runtime verification.
function Get-VeylComponentReadiness {
    $torRoot=Join-Path $script:Root 'Tor'
    $seen=@{}
    if(Test-Path -LiteralPath $torRoot -PathType Container){
        try {
            foreach($item in (Get-ChildItem -LiteralPath $torRoot -Recurse -File -ErrorAction Stop)){
                $name=$item.Name.ToLowerInvariant()
                if($name -in @('tor.exe','lyrebird.exe','geoip','geoip6')){$seen[$name]=$true}
            }
        }catch { Set-Footer ('Component inventory could not read Tor directory: '+$_.Exception.Message) }
    }
    return [ordered]@{
        Tor=[bool]$seen['tor.exe']
        Lyrebird=[bool]$seen['lyrebird.exe']
        GeoIP=[bool]$seen['geoip']
        GeoIP6=[bool]$seen['geoip6']
        Tun2socks=(Test-Path -LiteralPath (Join-Path $script:Root 'tun2socks\tun2socks.exe') -PathType Leaf)
        Wintun=(Test-Path -LiteralPath (Join-Path $script:Root 'tun2socks\wintun.dll') -PathType Leaf)
    }
}
function Get-VeylMissingNames($Snapshot) {
    $names=New-Object 'System.Collections.Generic.List[string]'
    foreach($name in @('Tor','Lyrebird','GeoIP','GeoIP6','Tun2socks','Wintun')){
        if(-not [bool]$Snapshot[$name]){$names.Add($name)}
    }
    return ,$names.ToArray()
}
function Set-VeylChip([string]$Chip,[string]$TextName,[bool]$Ready) {
    $bg=$script:Window.Resources['TT.Glow'];$fg=$script:Window.Resources['TT.Accent']
    if(-not $Ready){$bg=$script:Window.Resources['TT.SurfaceAlt'];$fg=$script:Window.Resources['TT.Warning']}
    $script:Ui[$Chip].Background=$bg
    $script:Ui[$TextName].Foreground=$fg
    $script:Ui[$TextName].Text=if($Ready){'Ready'}else{'Missing'}
    $script:Ui[$Chip].ToolTip=if($Ready){'File found. Network operation and signature not verified by this indicator.'}else{'Required file not found; see missing items below.'}
}
function Refresh-VeylComponentReadiness {
    if(-not $script:UiReady){return}
    $data=Get-VeylComponentReadiness
    $script:LastReadinessSnapshot=$data
    $names=Get-VeylMissingNames $data
    foreach($n in @('Tor','Lyrebird','GeoIP','GeoIP6','Tun2socks','Wintun')){
        Set-VeylChip ('Chip'+$n) ('State'+$n) ([bool]$data[$n])
    }
    if($names.Count -eq 0){
        $script:Ui.InventorySummary.Text='All six required component files are present. No missing downloads are needed.'
        $script:Ui.MissingComponentsPanel.Visibility=[System.Windows.Visibility]::Collapsed
    }else{
        $script:Ui.InventorySummary.Text=($names.Count.ToString()+' missing of 6 required component files. Only missing items appear below.')
        $script:Ui.MissingComponentsPanel.Visibility=[System.Windows.Visibility]::Visible
        $script:Ui.MissingComponentsList.Children.Clear()
        $instructions=@{Tor='Download and verify a signed Tor Expert Bundle, then install';Lyrebird='Install the signed Tor Expert Bundle (obfs4 transport)';GeoIP='Install the signed Tor Expert Bundle (GeoIP data)';GeoIP6='Install the signed Tor Expert Bundle (IPv6 GeoIP data)';Tun2socks='Download the verified helper pair or import trusted binaries';Wintun='Download the verified helper pair or import trusted binaries'}
        foreach($name in $names){
            $line=New-Object System.Windows.Controls.TextBlock
            $line.Text='• '+$name+' — '+$instructions[$name]
            $line.Foreground=$script:Window.Resources['TT.Text']
            $line.Margin=[System.Windows.Thickness]::new(0,2,0,4)
            $line.TextWrapping=[System.Windows.TextWrapping]::Wrap
            [void]$script:Ui.MissingComponentsList.Children.Add($line)
        }
    }
    $needHelpers=(-not [bool]$data.Tun2socks -or -not [bool]$data.Wintun)
    $script:Ui.BtnProvisionHelpers.Visibility=if($needHelpers){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    $script:Ui.BtnImportComponents.Visibility=if($names.Count -gt 0){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    $bridgeLines=@((Read-Text $script:BridgesPath) -split '\r?\n' | Where-Object {$_.Trim() -and -not $_.Trim().StartsWith('#')})
    $bridgesReady=$false
    if($bridgeLines.Count -gt 0){try{$bridgesReady=((Validate-Bridges ($bridgeLines -join "`n")) -gt 0)}catch{}}
    Set-VeylChip 'ChipBridges' 'StateBridges' $bridgesReady
    if(-not $bridgesReady){$script:Ui.StateBridges.Text='Missing'}
    $verified=$false
    try{
        $record=Read-Json $script:VerifiedPackagePath
        $verified=($record -and [string]$record.status -eq 'Verified' -and (Test-Path -LiteralPath ([string]$record.package) -PathType Leaf))
    }catch{}
    Set-VeylChip 'ChipSignedUpdate' 'StateSignedUpdate' ([bool]$verified)
    $script:Ui.StateSignedUpdate.Text=if($verified){'Verified staged'}else{'Not staged'}
    return $data
}

# Reopenable welcome/setup wizard. Opening a page never downloads binaries or changes routing.
function Show-VeylSetupGuide([bool]$FirstRun=$false) {
    if(-not $script:UiReady){return}
    $snapshot=Get-VeylComponentReadiness
    $missing=Get-VeylMissingNames $snapshot
    $missingText=if($missing.Count -eq 0){'All six required files were found.'}else{'Only missing files: '+($missing -join ', ')+'.'}
    $bridgeLines=@((Read-Text $script:BridgesPath) -split '\r?\n' | Where-Object {$_.Trim() -and -not $_.Trim().StartsWith('#')})
    $bridgesReady=$false
    if($bridgeLines.Count -gt 0){try{$bridgesReady=((Validate-Bridges ($bridgeLines -join "`n")) -gt 0)}catch{}}
    $bridgeStatus='No structurally valid saved obfs4 bridges were found. Request lines, validate and save them.'
    $requirementsPresent=($missing.Count -eq 0 -and $bridgesReady)
    $dialogXaml=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="VeylRoute setup guide" Width="720" Height="685" MinHeight="470" MaxHeight="780"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResize" ShowInTaskbar="False"
        FontFamily="Segoe UI" FontSize="13">
 <Border Name="GuideShell" BorderThickness="1" Padding="22">
  <DockPanel LastChildFill="True">
   <StackPanel DockPanel.Dock="Top" Margin="0,0,0,16">
    <TextBlock Name="GuideTitle" Text="Welcome to VeylRoute" FontSize="24" FontWeight="SemiBold"/>
    <TextBlock Name="GuideIntro" Text="This guide only displays setup requirements that still need attention." TextWrapping="Wrap" Margin="0,7,0,0"/>
   </StackPanel>
   <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,13,0,0">
    <Button Name="GuideClose" Content="Close guide" MinWidth="124" Height="40"/>
   </StackPanel>
   <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <StackPanel Margin="0,0,8,0">
     <Border Name="GuideCard1" CornerRadius="12" Padding="16" Margin="0,0,0,11"><StackPanel>
      <TextBlock Name="GuideH1" Text="01  Install required components" FontSize="16" FontWeight="SemiBold"/>
      <TextBlock Name="GuideMissing" TextWrapping="Wrap" Margin="0,7,0,9"/>
      <TextBlock Name="GuideDesc1" Text="Download or import Tor + lyrebird + GeoIP data, Wintun and tun2socks. Tor downloads must pass signature verification before installation." TextWrapping="Wrap" Margin="0,0,0,11"/>
      <Button Name="GuideGoUpdates" Tag="Updates" Content="Open component setup" MinWidth="190" HorizontalAlignment="Left" Height="37"/>
     </StackPanel></Border>
     <Border Name="GuideCard2" CornerRadius="12" Padding="16" Margin="0,0,0,11"><StackPanel>
      <TextBlock Name="GuideH2" Text="02  Configure obfs4 bridges" FontSize="16" FontWeight="SemiBold"/>
      <TextBlock Name="GuideBridgeStatus" TextWrapping="Wrap" Margin="0,7,0,9"/>
      <TextBlock Name="GuideDesc2" Text="Request bridge lines from the official Tor Project page, paste complete lines into VeylRoute, validate and Save configuration. Until connected, the request site opens using your normal Internet connection." TextWrapping="Wrap" Margin="0,0,0,11"/>
      <Button Name="GuideGoBridges" Tag="Bridges" Content="Open bridge setup" MinWidth="190" HorizontalAlignment="Left" Height="37"/>
     </StackPanel></Border>
     <Border Name="GuideCard3" CornerRadius="12" Padding="16" Margin="0,0,0,11"><StackPanel>
      <TextBlock Name="GuideH3" Text="03  Choose routing and privacy settings" FontSize="16" FontWeight="SemiBold"/>
      <TextBlock Name="GuideDesc3" Text="SystemWide uses the protected system route. SelectedAppsOnly routes only selected apps through Tor; other Windows traffic and system DNS remain direct. Review DNS, exit countries and application rules, then Save configuration." TextWrapping="Wrap" Margin="0,7,0,11"/>
      <Button Name="GuideGoDashboard" Tag="Dashboard" Content="Open connection settings" MinWidth="190" HorizontalAlignment="Left" Height="37"/>
     </StackPanel></Border>
     <Border Name="GuideCard4" CornerRadius="12" Padding="16" Margin="0,0,0,11"><StackPanel>
      <TextBlock Name="GuideH4" Text="04  Preflight, connect and verify" FontSize="16" FontWeight="SemiBold"/>
      <TextBlock Name="GuideDesc4" Text="Run Preflight before Connect. Correct every blocker shown on screen. After connecting, run Health Check. Disconnect restores normal Windows network settings; Exit GUI only closes the controller." TextWrapping="Wrap" Margin="0,7,0,11"/>
      <Button Name="GuideGoPreflight" Tag="Dashboard" Content="Open Preflight / Connect" MinWidth="190" HorizontalAlignment="Left" Height="37"/>
     </StackPanel></Border>
    </StackPanel>
   </ScrollViewer>
  </DockPanel>
 </Border>
</Window>
'@
    $dlg=[System.Windows.Markup.XamlReader]::Parse($dialogXaml)
    $dlg.Owner=$script:Window
    $dlg.FindName('GuideMissing').Text=$missingText
    $dlg.FindName('GuideBridgeStatus').Text=$bridgeStatus
    $dlg.FindName('GuideDesc1').Text='Download or import only the missing files listed above. Tor packages require signature verification before installation.'
    $dlg.FindName('GuideCard1').Visibility=if($missing.Count -gt 0){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    $dlg.FindName('GuideCard2').Visibility=if(-not $bridgesReady){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    # Routing mode remains configurable from the Overview sidebar; not an outstanding installation blocker.
    $dlg.FindName('GuideCard3').Visibility=[System.Windows.Visibility]::Collapsed
    $dlg.FindName('GuideCard4').Visibility=if($requirementsPresent){[System.Windows.Visibility]::Visible}else{[System.Windows.Visibility]::Collapsed}
    if($requirementsPresent){
        $dlg.FindName('GuideTitle').Text='Setup files and bridges found'
        $dlg.FindName('GuideIntro').Text='No components or bridge entries are missing. Review routing settings, run Preflight, and use Health Check after connecting. File presence does not prove network health.'
        $dlg.FindName('GuideH4').Text='Next: verify the connection'
    }
    $dlg.FindName('GuideShell').Background=$script:Window.Resources['TT.Background']
    $dlg.FindName('GuideShell').BorderBrush=$script:Window.Resources['TT.Border']
    foreach($name in @('GuideCard1','GuideCard2','GuideCard3','GuideCard4')){$dlg.FindName($name).Background=$script:Window.Resources['TT.Surface']}
    foreach($name in @('GuideTitle','GuideH1','GuideH2','GuideH3','GuideH4')){$dlg.FindName($name).Foreground=$script:Window.Resources['TT.Text']}
    foreach($name in @('GuideIntro','GuideMissing','GuideDesc1','GuideDesc2','GuideDesc3','GuideDesc4','GuideBridgeStatus')){$dlg.FindName($name).Foreground=$script:Window.Resources['TT.Muted']}
    foreach($name in @('GuideGoUpdates','GuideGoBridges','GuideGoDashboard','GuideGoPreflight')){
        $b=$dlg.FindName($name);$b.Style=$script:Window.Resources['PrimaryButton']
        $b.Add_Click({param($sender,$eventArgs)
            $w=[System.Windows.Window]::GetWindow($sender)
            $w.Tag=[string]$sender.Tag
            $w.Close()
        })
    }
    $closeButton=$dlg.FindName('GuideClose');$closeButton.Style=$script:Window.Resources['BaseButton']
    $closeButton.Add_Click({param($sender,$eventArgs)
        $w=[System.Windows.Window]::GetWindow($sender)
        $w.Close()
    })
    try{[void]$dlg.ShowDialog()}
    finally{
        if($FirstRun){
            try{
                $record=[ordered]@{format=1;shownAt=(Get-Date).ToString('o')}
                Replace-Atomic $script:SetupGuideFlagPath (($record|ConvertTo-Json -Depth 3)+"`r`n")
            }catch{Set-Footer ('Could not save guide acknowledgement: '+$_.Exception.Message)}
        }
    }
    $next=[string]$dlg.Tag
    if($next -in @('Updates','Bridges','Dashboard')){Show-Page $next}
}

# A current exit-count snapshot is a hint, not a guarantee of a usable Tor path.
function Load-VeylExitAvailability {
    $script:ExitAvailability=$null
    try{
        $obj=Read-Json $script:ExitAvailabilityPath
        if(-not $obj -or [int]$obj.format -ne 1 -or -not $obj.counts){throw 'Missing or invalid country-count data.'}
        $fetched=([datetime]::Parse([string]$obj.fetchedAtUtc)).ToUniversalTime()
        $published=([datetime]::Parse([string]$obj.relaysPublishedUtc)).ToUniversalTime()
        if(([datetime]::UtcNow-$fetched).TotalMinutes -gt 60 -or $fetched -gt [datetime]::UtcNow.AddMinutes(2) -or
           ([datetime]::UtcNow-$published).TotalHours -gt 6 -or $published -gt [datetime]::UtcNow.AddMinutes(15)){
            throw 'Relay information is stale.'
        }
        if([int]$obj.totalRunningExits -lt 1){throw 'No running exit records.'}
        $script:ExitAvailability=$obj
        $script:Ui.CountryAvailabilityNote.Text='Tor Project snapshot: '+[string]$obj.totalRunningExits+' running Exit relays, checked '+$fetched.ToLocalTime().ToString('HH:mm')+'. Counts are not guarantees.'
        $script:Ui.CountryAvailabilityNote.Foreground=$script:Window.Resources['TT.Accent']
    }catch{
        $script:Ui.CountryAvailabilityNote.Text='Exit availability unknown or expired. Refresh before choosing a country.'
        $script:Ui.CountryAvailabilityNote.Foreground=$script:Window.Resources['TT.Warning']
    }
}
function Get-VeylExitCount([string]$Code) {
    if(-not $script:ExitAvailability){return -1}
    $value=$script:ExitAvailability.counts.PSObject.Properties[$Code.ToLowerInvariant()]
    if($null -eq $value){return 0}
    return [int]$value.Value
}
function Assert-VeylSelectedExitAvailability {
    if(-not $script:ExitAvailability){return}
    $zero=@($script:Selected.Keys | Where-Object { (Get-VeylExitCount ([string]$_)) -eq 0 } | Sort-Object)
    if($zero.Count -gt 0){
        throw ('The latest Tor Project snapshot shows no running Exit-flag relays for: '+(($zero -join ', ').ToUpperInvariant())+'. Choose locations with relays or refresh the snapshot. No connection was started.')
    }
}
function Build-Countries {
    $script:CountryNames = @{}
    foreach ($culture in [System.Globalization.CultureInfo]::GetCultures([System.Globalization.CultureTypes]::SpecificCultures)) {
        try {
            $region = [System.Globalization.RegionInfo]::new($culture.Name)
            $code = $region.TwoLetterISORegionName.ToLowerInvariant()
            if ($code -match '^[a-z]{2}$' -and -not $script:CountryNames.ContainsKey($code)) {
                $script:CountryNames[$code] = $region.EnglishName
            }
        } catch {}
    }
}
function Update-CountryCount {
    $selected = @($script:Selected.Keys | Sort-Object)
    $list = if ($selected.Count -gt 0) { ($selected -join ', ').ToUpperInvariant() } else { 'select at least one' }
    $script:Ui.CountryCount.Text = "Selected: $($selected.Count)  |  $list"
}
function Refresh-CountryList {
    $query = $script:Ui.TxtCountrySearch.Text.Trim().ToLowerInvariant()
    $script:SuppressCountry = $true
    try {
        $script:Ui.ListCountries.Items.Clear()
        foreach ($entry in $script:CountryRows) {
            if ($query -and -not ($entry.Name.ToLowerInvariant().Contains($query) -or $entry.Code.Contains($query))) { continue }
            $check = New-Object System.Windows.Controls.CheckBox
            $count=Get-VeylExitCount $entry.Code
            if($count -eq 0 -and -not $script:Selected.ContainsKey($entry.Code)){continue}
            $check.Content = if($count -gt 0){$entry.Display+' - '+$count+' Exit relay(s)'}elseif($count -eq 0){$entry.Display+' - NO RUNNING EXIT RELAYS'}else{$entry.Display+' - availability unverified'}
            $check.Tag = $entry.Code
            $check.Foreground = $script:Window.Resources['TT.Text']
            $check.Margin = [System.Windows.Thickness]::new(2,5,2,5)
            $check.IsChecked = $script:Selected.ContainsKey($entry.Code)
            $check.Add_Checked({ param($sender,$eventArgs)
                if ($script:SuppressCountry) { return }
                $script:Selected[[string]$sender.Tag] = $true
                Refresh-FixedChoices
            })
            $check.Add_Unchecked({ param($sender,$eventArgs)
                if ($script:SuppressCountry) { return }
                [void]$script:Selected.Remove([string]$sender.Tag)
                Refresh-FixedChoices
            })
            [void]$script:Ui.ListCountries.Items.Add($check)
        }
    } finally { $script:SuppressCountry = $false }
    Update-CountryCount
}
function Refresh-FixedChoices {
    $prior = ''
    if ($script:Ui.CmbFixedCountry.SelectedItem -match '\(([A-Z]{2})\)$') { $prior = $Matches[1].ToLowerInvariant() }
    if (-not $prior) { $prior = [string](Field $script:Prefs 'PreferredCountry' '') }
    $script:Ui.CmbFixedCountry.Items.Clear()
    foreach ($entry in $script:CountryRows) {
        if ($script:Selected.ContainsKey($entry.Code)) { [void]$script:Ui.CmbFixedCountry.Items.Add($entry.Display) }
    }
    $index = 0
    for ($i=0; $i -lt $script:Ui.CmbFixedCountry.Items.Count; $i++) {
        if ([string]$script:Ui.CmbFixedCountry.Items[$i] -match "\($($prior.ToUpperInvariant())\)$") { $index=$i; break }
    }
    if ($script:Ui.CmbFixedCountry.Items.Count -gt 0) { $script:Ui.CmbFixedCountry.SelectedIndex = $index }
    $script:Ui.CmbFixedCountry.IsEnabled = ($script:Ui.CmbCountryMode.SelectedIndex -eq 0)
    Update-CountryCount
}
function Validate-Bridges([string]$Text) {
    $count=0
    foreach ($line in ($Text -split '\r?\n')) {
        $s=$line.Trim()
        if (-not $s -or $s.StartsWith('#')) { continue }
        if ($s -notmatch '^\s*(?:Bridge\s+)?obfs4\s+((?:\d{1,3}\.){3}\d{1,3}):(\d+)\s+') { throw 'Malformed or unsupported obfs4 entry. Preserve the complete bridge line.' }
        if (-not (Is-IPv4 $Matches[1]) -or [int]$Matches[2] -lt 1 -or [int]$Matches[2] -gt 65535) { throw 'A bridge IP address or port is invalid.' }
        $count++
    }
    if ($count -lt 1) { throw 'At least one valid obfs4 bridge is required.' }
    return $count
}
function Open-OfficialBridgePage {
    $url='https://bridges.torproject.org/'
    try {
        [void][System.Diagnostics.Process]::Start($url)
        Set-Footer 'Official Tor Project bridge service opened. Select obfs4, request bridges, then paste complete lines here.'
    } catch {
        Notice ('Cannot open the Tor Project bridge page automatically. Official URL: '+$url+' | '+$_.Exception.Message) 'Bridge request' ([System.Windows.MessageBoxImage]::Error)
    }
}
function Show-BridgeSetupOnFirstRun {
    $lines=@((Read-Text $script:BridgesPath) -split '\r?\n' | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    if ($lines.Count -gt 0) { return }
    Show-Page 'Bridges'
    $script:Ui.BridgeCount.Text='No bridges configured. Request obfs4 lines from Tor Project.'
    $promptFile=Join-Path $script:LogDir 'bridge-onboarding-shown.flag'
    if (Test-Path -LiteralPath $promptFile) { return }
    $open=Ask 'No obfs4 bridge lines were found. VeylRoute cannot connect through obfs4 without valid entries. Open the official Tor Project bridge request page in your browser now? Because Tor is not connected yet, this opens over your ordinary ISP connection. After requesting obfs4 bridges, paste the complete lines here and choose Save.' 'First-run bridge setup'
    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) { [void](New-Item -ItemType Directory -Path $script:LogDir -Force) }
        [IO.File]::WriteAllText($promptFile,(Get-Date -Format o),$script:Utf8)
    } catch {}
    if ($open) { Open-OfficialBridgePage }
}
function App-Line([string]$Line) {
    $text=$Line.Trim()
    if (-not $text -or $text.StartsWith('#')) { return '' }
    return $text.Trim('"')
}
function Load-Apps {
    $script:Ui.ListApps.Items.Clear()
    foreach ($line in ((Read-Text $script:AppsPath) -split '\r?\n')) {
        $app = App-Line $line
        if ($app) { [void]$script:Ui.ListApps.Items.Add($app) }
    }
}
function Apps-Text {
    $kept = @{}
    foreach ($item in $script:Ui.ListApps.Items) {
        $path = [string]$item
        if (-not [IO.Path]::IsPathRooted($path) -or -not $path.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "DIRECT bypass executable is missing or invalid: $path"
        }
        $kept[$path.ToLowerInvariant()]=$true
    }
    $seen=@{}
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ((Read-Text $script:AppsPath) -split '\r?\n')) {
        $path=App-Line $line
        if (-not $path) { $lines.Add($line); continue }
        $key=$path.ToLowerInvariant()
        if ($kept.ContainsKey($key) -and -not $seen.ContainsKey($key)) { $lines.Add($line); $seen[$key]=$true }
    }
    foreach ($path in $script:Ui.ListApps.Items) {
        $key=([string]$path).ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) { $lines.Add('"' + [string]$path + '"'); $seen[$key]=$true }
    }
    return ($lines.ToArray() -join "`r`n").TrimEnd("`r","`n") + "`r`n"
}
function Load-TorApps {
    $script:Ui.ListTorApps.Items.Clear()
    foreach($line in ((Read-Text $script:TorAppsPath) -split '\r?\n')){
        $path=App-Line $line
        if($path){[void]$script:Ui.ListTorApps.Items.Add($path)}
    }
}
function TorApps-Text {
    $items=New-Object 'System.Collections.Generic.List[string]'
    $items.Add('# TOR-only executables for SelectedAppsOnly mode. One absolute executable path per line.')
    $seen=@{}
    foreach($entry in $script:Ui.ListTorApps.Items){
        $path=([string]$entry).Trim()
        if(-not [IO.Path]::IsPathRooted($path) -or -not $path.EndsWith('.exe',[StringComparison]::OrdinalIgnoreCase) -or -not(Test-Path -LiteralPath $path -PathType Leaf)){
            throw "TOR-only executable is missing or invalid: $path"
        }
        $key=$path.ToLowerInvariant()
        if(-not $seen.ContainsKey($key)){$items.Add('"'+$path+'"');$seen[$key]=$true}
    }
    return ($items -join "`r`n") + "`r`n"
}
function Update-RouteWarning {
    if($script:Ui.CmbRouteMode.SelectedIndex -eq 1){
        $script:Ui.LblRouteWarning.Text='SelectedAppsOnly: Windows and system DNS stay DIRECT. Only listed executables use Tor; selected apps have individual firewall protections.'
    }else{
        $script:Ui.LblRouteWarning.Text='SystemWide: IPv4 TCP and strict DoH use Tor. Explicit DIRECT-bypass applications use your ISP.'
    }
}
function Preset-Name([string]$Primary,[string]$Secondary,[string]$Endpoint) {
    foreach ($preset in $script:DohPresets) {
        if ($preset.Primary -eq $Primary -and $preset.Secondary -eq $Secondary -and $preset.Endpoint -eq $Endpoint) { return [string]$preset.Name }
    }
    return 'Custom'
}
function Update-DohPresetFromText {
    if ($script:SuppressDoh) { return }
    $name=Preset-Name $script:Ui.TxtDoh1.Text.Trim() $script:Ui.TxtDoh2.Text.Trim() $script:Ui.TxtDohEndpoint.Text.Trim()
    if ([string]$script:Ui.CmbDohProvider.SelectedItem -ne $name) {
        $script:SuppressDoh=$true
        try { $script:Ui.CmbDohProvider.SelectedItem=$name }
        finally { $script:SuppressDoh=$false }
    }
}
function Load-Config {
    $script:Settings=Read-Json $script:ConfigPath
    if ($null -eq $script:Settings) { throw 'Configuration settings.json is missing or empty.' }
    $script:Prefs=Read-Json $script:PrefsPath
    $script:Selected=@{}
    $initial=([string](Field $script:Settings 'ExitCountry' 'us')).ToLowerInvariant()
    $stored=@(Field $script:Prefs 'SelectedCountries' @(Field $script:Settings 'ExitCountries' @($initial)))
    foreach ($value in $stored) {
        $code=([string]$value).Trim().ToLowerInvariant()
        if ($code -match '^[a-z]{2}$') { $script:Selected[$code]=$true }
    }
    if ($script:Selected.Count -eq 0) { $script:Selected[$initial]=$true }
    foreach ($code in $script:Selected.Keys) {
        if (-not $script:CountryNames.ContainsKey($code)) { $script:CountryNames[$code]=$code.ToUpperInvariant() }
    }
    $script:CountryRows=@($script:CountryNames.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{Code=$_.Key; Name=$_.Value; Display=('{0} ({1})' -f $_.Value,$_.Key.ToUpperInvariant())}
    } | Sort-Object Name,Code)
    $mode=([string](Field $script:Prefs 'ExitMode' $(if ([bool](Field $script:Settings 'ExitUsePool' $false)) { 'pool' } else { 'fixed' }))).ToLowerInvariant()
    $script:Ui.CmbCountryMode.SelectedIndex = switch ($mode) { 'random' {1} 'pool' {2} default {0} }
    $script:Ui.TxtCountrySearch.Text=''
    Refresh-CountryList
    Refresh-FixedChoices
    $preferred=[string](Field $script:Prefs 'PreferredCountry' $initial)
    for ($i=0;$i -lt $script:Ui.CmbFixedCountry.Items.Count;$i++) {
        if (([string]$script:Ui.CmbFixedCountry.Items[$i]).EndsWith('('+$preferred.ToUpperInvariant()+')')) { $script:Ui.CmbFixedCountry.SelectedIndex=$i; break }
    }
    $script:Ui.CbStrictCountry.IsChecked=[bool](Field $script:Settings 'StrictExitCountry' $false)
    $script:Ui.TxtDoh1.Text=[string](Field $script:Settings 'DohPrimary' '1.1.1.1')
    $script:Ui.TxtDoh2.Text=[string](Field $script:Settings 'DohSecondary' '1.0.0.1')
    $script:Ui.TxtDohEndpoint.Text=[string](Field $script:Settings 'DohTemplate' 'https://cloudflare-dns.com/dns-query')
    $script:SuppressDoh=$true
    try { $script:Ui.CmbDohProvider.SelectedItem=Preset-Name $script:Ui.TxtDoh1.Text $script:Ui.TxtDoh2.Text $script:Ui.TxtDohEndpoint.Text }
    finally { $script:SuppressDoh=$false }
    $script:Ui.CbBlockPlainDns.IsChecked=[bool](Field $script:Settings 'BlockPlainDns' $true)
    $script:Ui.CbDisableIPv6.IsChecked=[bool](Field $script:Settings 'DisableIPv6' $true)
    $script:Ui.CbEdgeKill.IsChecked=[bool](Field $script:Settings 'EdgeKillSwitch' $true)
    $script:Ui.CbDisableQuic.IsChecked=[bool](Field $script:Settings 'DisableEdgeQuic' $true)
    $script:Ui.CbOpenEdge.IsChecked=[bool](Field $script:Settings 'OpenEdgeAfterConnect' $false)
    $script:Ui.CbFreshState.IsChecked=[bool](Field $script:Settings 'FreshTorStateOnNewPC' $true)
    $script:Ui.CbEnableApps.IsChecked=[bool](Field $script:Settings 'EnableAppExclusions' $true)
    $script:Ui.CbEnableTorApps.IsChecked=[bool](Field $script:Settings 'EnableSelectedTorApps' $true)
    $script:Ui.CbTorAppKillSwitch.IsChecked=[bool](Field $script:Settings 'TorAppKillSwitch' $true)
    $script:Ui.CbBlockTorAppUdp.IsChecked=[bool](Field $script:Settings 'BlockTorAppUdp' $true)
    $requestedMode=[string](Field $script:Prefs 'RoutingMode' 'SystemWide')
    $script:Ui.CmbRouteMode.SelectedIndex=if($requestedMode.ToLowerInvariant() -eq 'selectedappsonly'){1}else{0}
    Update-RouteWarning
    $script:Ui.TxtSocksPort.Text=[string](Field $script:Settings 'SocksPort' 9050)
    $script:Ui.TxtRouteMetric.Text=[string](Field $script:Settings 'RouteMetric' 5)
    $script:Ui.TxtBootstrap.Text=[string](Field $script:Settings 'BootstrapTimeoutSeconds' 240)
    $script:Ui.CbRetry.IsChecked=[bool](Field $script:Prefs 'RetryTransient' $true)
    $script:Ui.TxtAttempts.Text=[string](Field $script:Prefs 'RetryAttempts' 3)
    $script:Ui.TxtProbeDelay.Text=[string](Field $script:Settings 'TransparentProbeDelaySeconds' 3)
    $existingBridges=Read-Text $script:BridgesPath
    $liveBridgeLines=@($existingBridges -split '\r?\n' | Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('#') })
    $script:Ui.TxtBridges.Text=if($liveBridgeLines.Count -eq 0){ '' }else{ $existingBridges }
    Load-Apps
    Load-TorApps
    try { $script:Ui.BridgeCount.Text="Configured bridges: $(Validate-Bridges $script:Ui.TxtBridges.Text)" } catch { $script:Ui.BridgeCount.Text='Bridge entries require review' }
    Set-Footer 'Configuration loaded from disk. Save to apply changes on next connection.'
}

# The config write protocol is intentionally conservative: all original files
# are copied to a timestamped folder before any file is replaced. On failure,
# every changed file is restored from that snapshot. No active session is edited.
function Replace-Atomic([string]$Path,[string]$Content) {
    $id=[guid]::NewGuid().ToString('N')
    $temp=$Path+'.ttgui-'+$id+'.tmp'
    $replaceBackup=$Path+'.ttgui-'+$id+'.replace.bak'
    [IO.File]::WriteAllText($temp,$Content,$script:Utf8)
    $done=$false
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) { [IO.File]::Replace($temp,$Path,$replaceBackup) }
        else { [IO.File]::Move($temp,$Path) }
        $done=$true
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        if ($done -and (Test-Path -LiteralPath $replaceBackup)) { Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue }
    }
}
function Save-Config([bool]$ForStart=$false) {
    Assert-Editable
    if($ForStart){Assert-VeylSelectedExitAvailability}
    $codes=@($script:Selected.Keys | Sort-Object)
    if ($codes.Count -lt 1) { throw 'Select at least one allowed exit country.' }
    $mode=switch ($script:Ui.CmbCountryMode.SelectedIndex) { 1 {'random'} 2 {'pool'} default {'fixed'} }
    $preferred=$codes[0]
    if ([string]$script:Ui.CmbFixedCountry.SelectedItem -match '\(([A-Z]{2})\)$') { $preferred=$Matches[1].ToLowerInvariant() }
    if ($preferred -notin $codes) { $preferred=$codes[0] }
    $effective=$preferred
    if ($mode -eq 'random') {
        if ($ForStart) { $effective=$codes[(Get-Random -Minimum 0 -Maximum $codes.Count)] }
        else {
            $saved=([string](Field $script:Settings 'ExitCountry' '')).ToLowerInvariant()
            if ($saved -in $codes) { $effective=$saved }
        }
    }
    $d1=$script:Ui.TxtDoh1.Text.Trim();$d2=$script:Ui.TxtDoh2.Text.Trim();$endpoint=$script:Ui.TxtDohEndpoint.Text.Trim()
    if (-not (Is-IPv4 $d1) -or -not (Is-IPv4 $d2) -or $d1 -eq $d2) { throw 'DoH addresses must be two distinct, valid IPv4 addresses.' }
    $uri=$null
    if (-not [Uri]::TryCreate($endpoint,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https') { throw 'DoH endpoint must be a valid HTTPS URL.' }
    $ports=Parse-Integer $script:Ui.TxtSocksPort.Text 1 65535 'SOCKS port'
    $metric=Parse-Integer $script:Ui.TxtRouteMetric.Text 1 9999 'Route metric'
    $bootstrap=Parse-Integer $script:Ui.TxtBootstrap.Text 30 900 'Bootstrap timeout'
    $attempts=Parse-Integer $script:Ui.TxtAttempts.Text 1 6 'Probe attempts'
    $delay=Parse-Integer $script:Ui.TxtProbeDelay.Text 1 20 'Probe delay'
    $bridgeCount=Validate-Bridges $script:Ui.TxtBridges.Text
    $appsText=Apps-Text
    $torAppsText=TorApps-Text
    if($script:Ui.CmbRouteMode.SelectedIndex -eq 1 -and $script:Ui.ListTorApps.Items.Count -lt 1){
        throw 'SelectedAppsOnly requires at least one TOR application. Add an executable on Application routing.'
    }
    foreach($direct in $script:Ui.ListApps.Items){
        foreach($torApp in $script:Ui.ListTorApps.Items){
            if([string]::Equals([string]$direct,[string]$torApp,[StringComparison]::OrdinalIgnoreCase)){
                throw "The same executable cannot appear in DIRECT and TOR-only lists: $direct"
            }
        }
    }
    if (-not [bool]$script:Ui.CbBlockPlainDns.IsChecked -or -not [bool]$script:Ui.CbDisableIPv6.IsChecked -or -not [bool]$script:Ui.CbEdgeKill.IsChecked) {
        if (-not (Ask 'One or more fail-closed / leak safeguards would be disabled. This may expose traffic outside Tor. Save these settings anyway?' 'Security warning')) {
            throw 'Save cancelled. Security controls were not changed.'
        }
    }
    $settings=(Read-Text $script:ConfigPath) | ConvertFrom-Json -ErrorAction Stop
    Set-Field $settings 'ExitCountry' $effective
    Set-Field $settings 'ExitCountries' ([string[]]$codes)
    Set-Field $settings 'ExitUsePool' ($mode -eq 'pool')
    Set-Field $settings 'StrictExitCountry' ([bool]$script:Ui.CbStrictCountry.IsChecked)
    Set-Field $settings 'DohPrimary' $d1; Set-Field $settings 'DohSecondary' $d2; Set-Field $settings 'DohTemplate' $endpoint
    Set-Field $settings 'SocksPort' $ports; Set-Field $settings 'RouteMetric' $metric; Set-Field $settings 'BootstrapTimeoutSeconds' $bootstrap
    Set-Field $settings 'BlockPlainDns' ([bool]$script:Ui.CbBlockPlainDns.IsChecked)
    Set-Field $settings 'DisableIPv6' ([bool]$script:Ui.CbDisableIPv6.IsChecked)
    Set-Field $settings 'EdgeKillSwitch' ([bool]$script:Ui.CbEdgeKill.IsChecked)
    Set-Field $settings 'DisableEdgeQuic' ([bool]$script:Ui.CbDisableQuic.IsChecked)
    Set-Field $settings 'OpenEdgeAfterConnect' ([bool]$script:Ui.CbOpenEdge.IsChecked)
    Set-Field $settings 'FreshTorStateOnNewPC' ([bool]$script:Ui.CbFreshState.IsChecked)
    Set-Field $settings 'EnableAppExclusions' ([bool]$script:Ui.CbEnableApps.IsChecked)
    Set-Field $settings 'EnableSelectedTorApps' ([bool]$script:Ui.CbEnableTorApps.IsChecked)
    Set-Field $settings 'TorAppKillSwitch' ([bool]$script:Ui.CbTorAppKillSwitch.IsChecked)
    Set-Field $settings 'BlockTorAppUdp' ([bool]$script:Ui.CbBlockTorAppUdp.IsChecked)
    Set-Field $settings 'TransparentProbeAttempts' $(if ([bool]$script:Ui.CbRetry.IsChecked) { $attempts } else { 1 })
    Set-Field $settings 'TransparentProbeDelaySeconds' $delay
    $prefs=[pscustomobject][ordered]@{
        FormatVersion=1; ExitMode=$mode; PreferredCountry=$preferred; SelectedCountries=[string[]]$codes;
        RetryTransient=[bool]$script:Ui.CbRetry.IsChecked; RetryAttempts=$attempts;
        RoutingMode=$(if($script:Ui.CmbRouteMode.SelectedIndex -eq 1){'SelectedAppsOnly'}else{'SystemWide'})
    }
    $changes=@(
        @{Path=$script:ConfigPath; Text=(($settings | ConvertTo-Json -Depth 30)+"`r`n")},
        @{Path=$script:PrefsPath; Text=(($prefs | ConvertTo-Json -Depth 12)+"`r`n")},
        @{Path=$script:AppsPath; Text=$appsText},
        @{Path=$script:TorAppsPath; Text=$torAppsText},
        @{Path=$script:BridgesPath; Text=[string]$script:Ui.TxtBridges.Text}
    )
    $backup=Join-Path $script:ConfigDir ('gui-backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    [void](New-Item -ItemType Directory -Path $backup -Force)
    $before=@{}; $modified=New-Object 'System.Collections.Generic.List[string]'
    foreach ($change in $changes) {
        $path=[string]$change.Path
        $before[$path]=if (Test-Path -LiteralPath $path) { Read-Text $path } else { $null }
        if ($null -ne $before[$path]) { [IO.File]::Copy($path,(Join-Path $backup ([IO.Path]::GetFileName($path))),$false) }
    }
    try {
        foreach ($change in $changes) {
            $path=[string]$change.Path
            if ($null -ne $before[$path] -and $before[$path] -ceq [string]$change.Text) { continue }
            # Track BEFORE replacing so even partial errors have a recovery copy.
            $modified.Add($path)
            Replace-Atomic $path ([string]$change.Text)
        }
    } catch {
        $reason=$_.Exception.Message
        for($i=$modified.Count-1;$i -ge 0;$i--) {
            $path=$modified[$i]
            try {
                if ($null -eq $before[$path]) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop } }
                else { Copy-Item -LiteralPath (Join-Path $backup ([IO.Path]::GetFileName($path))) -Destination $path -Force -ErrorAction Stop }
            } catch { $reason += " | rollback error: $($_.Exception.Message)" }
        }
        throw "Configuration was not saved; backup at $backup. $reason"
    }
    $script:Settings=$settings; $script:Prefs=$prefs
    $summary=if ($mode -eq 'pool') { 'Tor pool: ' + ($codes -join ', ').ToUpperInvariant() } else { 'Next exit request: ' + $effective.ToUpperInvariant() }
    Set-Footer "Saved. $summary | $bridgeCount obfs4 bridge(s)."
    [void](Refresh-VeylComponentReadiness)
    return $effective
}

function Read-StatusFields([string]$Text) {
    $data=@{}
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\s*([^:]+?)\s*:\s*(.+?)\s*$') { $data[$Matches[1].Trim().ToLowerInvariant()]=$Matches[2].Trim() }
    }
    return $data
}
# Overview privacy observations are evidence-limited. Local DoH / firewall state does not
# prove the absence of a DNS leak; no generic browser fingerprinting claims are made.
function Set-VeylPrivacyRow([string]$Key,[string]$Value,[string]$Note,[string]$Tone='Muted') {
    $script:Ui[$Key+'Value'].Text=$Value
    $script:Ui[$Key+'Note'].Text=$Note
    if($Tone -notin @('Accent','Warning','Danger','Muted')){$Tone='Muted'}
    $script:Ui[$Key+'Value'].Foreground=$script:Window.Resources['TT.'+$Tone]
}
function Reset-VeylPrivacy {
    if(-not $script:UiReady){return}
    $script:Ui.PrivacyHeadline.Text='Disconnected - no active traffic checks'
    $script:Ui.PrivacyCheckedAt.Text='Checks run automatically after a verified connection.'
    foreach($name in @('PrivacyTor','PrivacyDns','PrivacyIpv6','PrivacyFirewall')){
        Set-VeylPrivacyRow $name 'NOT TESTED' 'No active session' 'Muted'
    }
    Set-VeylPrivacyRow 'PrivacyLeak' 'UNVERIFIED' 'No external DNS-path test was performed' 'Warning'
    $script:Ui.PrivacyRemedy.Text='Connect first. VeylRoute will test its available network safeguards and show their actual results.'
}
function Set-VeylPrivacyPending {
    $script:Ui.PrivacyHeadline.Text='Connected - checking protection controls...'
    $script:Ui.PrivacyCheckedAt.Text='Automatic read-only Health/Status check starting shortly.'
    foreach($name in @('PrivacyTor','PrivacyDns','PrivacyIpv6','PrivacyFirewall')){
        Set-VeylPrivacyRow $name 'CHECKING' 'Awaiting fresh status data' 'Warning'
    }
    Set-VeylPrivacyRow 'PrivacyLeak' 'UNVERIFIED' 'External DNS path has not been measured' 'Warning'
    $script:Ui.PrivacyRemedy.Text='Do not assume leak-free operation while verification is pending.'
}
function Show-VeylPrivacyStatus([string]$Text,[bool]$FromCache=$false) {
    if(-not (Has-Session)){Reset-VeylPrivacy;return}
    $d=Read-StatusFields $Text
    $mode=[string]$d['routing mode']
    $selected=($mode -match '(?i)selectedappsonly')
    $healthy=([string]$d['overall'] -match '^HEALTHY')
    $isTor=if($selected){[string]$d['tor socks istor'] -match '^True'}else{[string]$d['system istor'] -match '^True'}
    $ip=if($selected){[string]$d['tor exit ip']}else{[string]$d['exit ip']}
    if($isTor -and $ip){Set-VeylPrivacyRow 'PrivacyTor' 'TOR VERIFIED' ('Exit IP: '+$ip+' (Tor Project response)') 'Accent'}
    elseif($healthy){Set-VeylPrivacyRow 'PrivacyTor' 'CHECK' 'No positive Tor-check response was found' 'Warning'}
    else{Set-VeylPrivacyRow 'PrivacyTor' 'NOT VERIFIED' 'Tor network check failed or is incomplete' 'Danger'}
    $dnsGood=$false
    if($selected){
        Set-VeylPrivacyRow 'PrivacyDns' 'SYSTEM DIRECT' 'SelectedAppsOnly keeps Windows/system DNS direct' 'Warning'
        Set-VeylPrivacyRow 'PrivacyLeak' 'DIRECT BY DESIGN' 'Selected-app DNS is not Tor-private in this mode' 'Warning'
    }else{
        $dohOk=([string]$d['strict doh'] -match '^ACTIVE / NO UDP FALLBACK')
        $resolution=([string]$d['dns resolution'] -match '^WORKING')
        $plainBlock=[string]$d['plain dns block']
        $blockOk=$false
        if($plainBlock -match '^(\d+)/(\d+)\s+rule'){
            $blockOk=([int]$Matches[1] -gt 0 -and [int]$Matches[1] -eq [int]$Matches[2])
        }
        $dnsGood=($dohOk -and $resolution -and $blockOk)
        if($dnsGood){Set-VeylPrivacyRow 'PrivacyDns' 'CONTROLS ACTIVE' 'Strict DoH, DNS resolution and plaintext-block rules checked' 'Accent'}
        else{Set-VeylPrivacyRow 'PrivacyDns' 'CHECK SETTINGS' 'DoH, resolution or DNS-block rule check was incomplete' 'Danger'}
        Set-VeylPrivacyRow 'PrivacyLeak' 'NOT PROVEN' 'DoH is encrypted, but the physical DNS path was not independently traced' 'Warning'
    }
    $v6=[string]$d['ipv6 egress controls']
    if($v6 -match '^ADAPTER IPv6 DISABLED / NO DEFAULT ROUTE'){
        Set-VeylPrivacyRow 'PrivacyIpv6' 'CONTROLS OBSERVED' 'Passive adapter and route inspection; no external IPv6 request sent' 'Accent'
    }elseif($v6 -match '^CHECK REQUIRED'){
        Set-VeylPrivacyRow 'PrivacyIpv6' 'EXPOSURE RISK' 'IPv6 adapter binding or default-route inspection needs correction' 'Danger'
    }elseif($selected){
        Set-VeylPrivacyRow 'PrivacyIpv6' 'SYSTEM DIRECT' 'SelectedAppsOnly is not system-wide IPv6 protection' 'Warning'
    }else{Set-VeylPrivacyRow 'PrivacyIpv6' 'NOT VERIFIED' 'IPv6 blocking is disabled or its passive check is unavailable' 'Warning'}
    $firewallKey=if($selected){'tor app firewall'}else{'edge kill-switch'}
    $rules=[string]$d[$firewallKey]
    if($rules -match '^(\d+)/(\d+)\s+rule' -and [int]$Matches[2] -gt 0 -and [int]$Matches[1] -eq [int]$Matches[2]){
        Set-VeylPrivacyRow 'PrivacyFirewall' 'RULES PRESENT' 'Named firewall rules exist; fail-closed behavior still needs testing' 'Accent'
    }else{Set-VeylPrivacyRow 'PrivacyFirewall' 'NOT VERIFIED' 'Required app/Edge rule not observed; check routing protection' 'Warning'}
    $script:Ui.PrivacyCheckedAt.Text=if($FromCache){'Saved observation for this session - fresh test pending'}else{'Checked '+(Get-Date -Format 'HH:mm:ss')+' | Auto recheck about every 3 minutes'}
    $script:Ui.PrivacyHeadline.Text=if($FromCache){'Previous session check - refreshing'}elseif($healthy -and $isTor -and ($dnsGood -or $selected)){'Core checks passed; external DNS-leak proof is still pending'}else{'One or more protection checks needs attention'}
    if($selected){
        $script:Ui.PrivacyRemedy.Text='For Tor-private system DNS use SystemWide mode. SelectedAppsOnly intentionally leaves Windows DNS direct.'
    }elseif(-not $isTor){
        $script:Ui.PrivacyRemedy.Text='Tor verification failed: disconnect safely and review the connection log before retrying.'
    }elseif(-not $dnsGood){
        $script:Ui.PrivacyRemedy.Text='Review DNS protection settings and firewall rules. Do not enable plaintext fallback to hide this warning.'
    }elseif($v6 -match '^CHECK REQUIRED'){
        $script:Ui.PrivacyRemedy.Text='Disconnect safely and review IPv6 adapter bindings and default routes before using the tunnel for privacy-sensitive work.'
    }else{
        $script:Ui.PrivacyRemedy.Text='Local safeguards checked. A physical-interface trace or independent controlled DNS resolver test is still needed to rule out DoH bypass.'
    }
}

function Populate-StatusCards([string]$Text) {
    $d=Read-StatusFields $Text
    if ($d.ContainsKey('exit ip')) { $script:Ui.CardIp.Text=$d['exit ip']; $script:Ui.CardIpNote.Text='Last diagnostic probe' }
    elseif ($d.ContainsKey('tor exit ip')) { $script:Ui.CardIp.Text=$d['tor exit ip'];$script:Ui.CardIpNote.Text='Last successful start' }
    if ($d.ContainsKey('country')) { $script:Ui.CardCountry.Text=$d['country'].Split(' ')[0]; $script:Ui.CardCountryNote.Text=$d['country'] }
    elseif ($d.ContainsKey('reported country')) { $script:Ui.CardCountry.Text=$d['reported country'].Split(' ')[0];$script:Ui.CardCountryNote.Text='Startup GeoIP observation' }
    if ($d.ContainsKey('strict doh')) { $script:Ui.CardDns.Text=if ($d['strict doh'] -match 'ACTIVE') {'ACTIVE'} else {'CHECK'}; $script:Ui.CardDnsNote.Text=$d['strict doh'] }
    elseif ($d.ContainsKey('dns')) { $script:Ui.CardDns.Text='Strict DoH'; $script:Ui.CardDnsNote.Text='Reported at startup' }
    if (($d.ContainsKey('system dns') -and $d['system dns'] -match 'DIRECT') -or
        ($d.ContainsKey('routing mode') -and $d['routing mode'] -match '(?i)selectedappsonly')) {
        $script:Ui.CardDns.Text='DIRECT'
        $script:Ui.CardDnsNote.Text='SelectedAppsOnly uses Windows system DNS, not Tor-private DNS'
    }
    if($d.ContainsKey('routing mode')){
        $script:Ui.CardRoute.Text=if($d['routing mode'] -match '(?i)selectedappsonly'){'SELECTED APPS'}else{'SYSTEMWIDE'}
        $script:Ui.CardRouteNote.Text=[string]$d['routing mode']
    }
    if ($d.ContainsKey('wintun')) { $script:Ui.CardRoute.Text='WINTUN'; $script:Ui.CardRouteNote.Text=$d['wintun'] }
    elseif ($d.ContainsKey('wintun adapter')) { $script:Ui.CardRoute.Text='WINTUN'; $script:Ui.CardRouteNote.Text=$d['wintun adapter'] }
}
function Clear-StatusCards {
    foreach ($key in @('CardIp','CardCountry','CardDns','CardRoute')) { $script:Ui[$key].Text='--' }
    foreach ($key in @('CardIpNote','CardCountryNote','CardDnsNote','CardRouteNote')) { $script:Ui[$key].Text='Not verified' }
}
function Get-SessionKey {
    if (-not (Has-Session)) { return '' }
    try {
        $session=Read-Json $script:StatePath
        return ([string](Field $session 'StartedAt' ''))
    } catch { return '' }
}
function Save-StatusCache([string]$Raw) {
    $key=Get-SessionKey
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    $obj=[ordered]@{ format=1; sessionStartedAt=$key; verifiedAt=(Get-Date).ToString('o'); text=$Raw }
    $json=$obj | ConvertTo-Json -Depth 6
    $temp=$script:StatusCachePath+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temp,$json,$script:Utf8)
    if (Test-Path -LiteralPath $script:StatusCachePath) { Move-Item -LiteralPath $temp -Destination $script:StatusCachePath -Force }
    else { [IO.File]::Move($temp,$script:StatusCachePath) }
}
function Load-StatusCache {
    if (-not (Has-Session)) { return }
    $key=Get-SessionKey
    if ([string]::IsNullOrWhiteSpace($key)) { return }
    try {
        $cache=Read-Json $script:StatusCachePath
        if ($cache -and $cache.format -eq 1 -and [string]$cache.sessionStartedAt -eq $key) {
            Populate-StatusCards ([string]$cache.text)
            Show-VeylPrivacyStatus ([string]$cache.text) -FromCache $true
            $stamp=[datetime]::Parse([string]$cache.verifiedAt)
            $script:Ui.AutoRefreshNotice.Text=('Last saved status: '+$stamp.ToLocalTime().ToString('g')+' | Live verification is pending.')
            $script:StatusCacheLoaded=$true
        }
    } catch {}
}
# Live progress is read from a temporary JSON record created by the actual background worker.
# Displayed percentages are per download. Indeterminate means the server did not report a size,
# or the operation is verifying, extracting, installing, or waiting on the network.
function Refresh-VeylTransferUI {
    if(-not $script:UiReady){return}
    $running=($script:BusyAction -in @('ProvisionHelpers','ImportComponents','UpdatePrepare','UpdateInstall','UpdateRollback') -and (In-Progress))
    $record=$null
    try {$record=Read-Json $script:TransferProgressPath}catch{}
    $action=if($record){[string]$record.action}else{''}
    $selected=$script:TransferVisibleAction
    if($selected -and ($null -eq $record -or $action -ne $selected)){
        $script:Ui.TransferPanel.Visibility=[System.Windows.Visibility]::Visible
        if($running){
            $elapsed=([datetime]::UtcNow-$script:TransferStartedUtc).TotalSeconds
            if($elapsed -ge 15){
                $script:Ui.TransferStage.Text='Waiting for background worker telemetry'
                $script:Ui.TransferDescription.Text='No transfer receipt yet. If this continues, the worker result will be shown as an error; no installation is assumed.'
            }
            $script:Ui.TransferStatus.Text='WAITING'
        }else{
            $script:Ui.TransferStatus.Text='NOT VERIFIED'
            $script:Ui.TransferStage.Text='Worker ended without a component receipt'
            $script:Ui.TransferDescription.Text='No matching final transfer record. Check the on-screen error guidance and refresh component status.'
            $script:Ui.TransferBytes.Text='No completed transfer confirmed'
            $script:Ui.TransferLocation.Text='No installed destination confirmed'
            $script:Ui.TransferProgress.IsIndeterminate=$false
            $script:Ui.TransferProgress.Value=0
        }
        return
    }
    if(-not $record){return}
    if($running -and $action -ne $script:BusyAction){return}
    if($script:TransferStartedUtc -gt [datetime]::MinValue -and $action -eq $script:TransferVisibleAction){
        try {
            $time=([datetime]::Parse([string]$record.updatedUtc)).ToUniversalTime()
            if($time -lt $script:TransferStartedUtc.AddSeconds(-2)){
                if(-not $running){
                    $script:Ui.TransferPanel.Visibility=[System.Windows.Visibility]::Visible
                    $script:Ui.TransferStatus.Text='NOT VERIFIED'
                    $script:Ui.TransferStage.Text='The worker ended without a fresh result'
                    $script:Ui.TransferDescription.Text='No completion record was written for this attempt. Review the actionable error dialog; do not assume that anything installed.'
                    $script:Ui.TransferProgress.IsIndeterminate=$false
                    $script:Ui.TransferProgress.Value=0
                    $script:Ui.TransferBytes.Text='No confirmed bytes received'
                    $script:Ui.TransferLocation.Text='No confirmed installation target'
                }
                return
            }
        }catch{return}
    }
    $state=[string]$record.state
    $stage=[string]$record.stage
    $script:Ui.TransferPanel.Visibility=[System.Windows.Visibility]::Visible
    if($running){$script:TransferVisibleAction=$action}
    $script:Ui.TransferStatus.Text=if($state -eq 'Completed'){switch($action){'UpdatePrepare'{'VERIFIED / STAGED'}'UpdateInstall'{'INSTALLED'}'UpdateRollback'{'RESTORED'}'ImportComponents'{'IMPORTED'}default{'INSTALLED'}}}elseif($state -eq 'Failed'){'FAILED'}elseif($running){'WORKING'}else{'PREVIOUS RESULT'}
    $script:Ui.TransferStage.Text=$stage
    $pc=[int]$record.percent
    $incomplete=($state -eq 'Running' -and -not $running)
    if($incomplete){
        $script:Ui.TransferStatus.Text='NOT VERIFIED'
        $script:Ui.TransferDescription.Text='A previous operation did not record completion. Inspect the component badges and retry after checking any error message.'
    }else{
        $script:Ui.TransferDescription.Text=[string]$record.detail
    }
    $script:Ui.TransferProgress.IsIndeterminate=($pc -lt 0 -and $running)
    $script:Ui.TransferProgress.Value=if($pc -ge 0){$pc}else{0}
    $received=[long]$record.bytes;$total=[long]$record.total
    $script:Ui.TransferBytes.Text=if($total -gt 0){('{0:N1} / {1:N1} MB ({2}%)' -f ($received/1MB),($total/1MB),$pc)}elseif($received -gt 0){('{0:N1} MB received' -f ($received/1MB))}else{if($state -eq 'Completed'){'Files checked'}else{'Awaiting transfer or checking files'}}
    $destination=[string]$record.destination
    $script:Ui.TransferLocation.Text=if($destination){'Target: '+$destination}else{'No destination written yet.'}
}
function Refresh-UpdateStage {
    $label='No verified binary package staged. Prepare and verify an official stable Expert Bundle first.'
    try {
        $r=Read-Json $script:VerifiedPackagePath
        if ($r -and [string]$r.status -eq 'Verified') {
            $label='Signature verified: Expert Bundle '+[string]$r.expertBundle+'. SHA256 '+([string]$r.sha256).Substring(0,12)+'...'
        }
    } catch {}
    try {
        $r=Read-Json $script:InstalledPackagePath
        if ($r) { $label += ' | Installed Tor '+[string]$r.installedVersion+'; rollback retained.' }
    } catch {}
    try{
        $attempt=Read-Json $script:PrepareStagePath
        if($attempt -and [string]$attempt.status -eq 'Failed'){
            $label += ' | Latest attempt failed at: '+[string]$attempt.stage+'. '+[string]$attempt.detail
        }
    }catch{}
    $script:Ui.UpdateStage.Text=$label
    if($script:UiReady){[void](Refresh-VeylComponentReadiness)}
}
function Set-TrayArtwork([string]$Kind) {
    if (-not $script:TrayIcon -or -not $script:TrayArt.ContainsKey($Kind) -or $script:TrayCurrent -eq $Kind) { return }
    try {
        $script:TrayIcon.Icon=$script:TrayArt[$Kind]; $script:TrayCurrent=$Kind
        $icoFile=Join-Path $PSScriptRoot ('assets\VeylRoute-'+$Kind+'.ico')
        if($script:Window -and (Test-Path -LiteralPath $icoFile -PathType Leaf)){
            $script:Window.Icon=[System.Windows.Media.Imaging.BitmapFrame]::Create(([Uri]::new($icoFile,[UriKind]::Absolute)))
        }
    }catch{}
}
function Auto-StatusPulse {
    if (-not $script:UiReady -or -not (Has-Session) -or (In-Progress)) { return }
    if ((Get-Date) -lt $script:AutoStatusInitialDue) { return }
    if (((Get-Date) - $script:AutoStatusLastStart).TotalSeconds -lt $script:AutoStatusEverySeconds) { return }
    # Status is the EXISTING full read-only script; its external Tor check may take 20s.
    # It runs entirely in a hidden background worker, never on the WPF UI thread.
    $script:AutoStatusLastStart=Get-Date
    $script:Ui.AutoRefreshNotice.Text='Automatic status verification running in background...'
    try { Run-Action 'Status' -Automatic $true } catch {
        $script:Ui.AutoRefreshNotice.Text='Automatic status check could not start.'
        Present-VeylIssue (Get-VeylIssue -Action 'Automatic status' -Text $_.Exception.Message) -Automatic $true
    }
}
function Update-SessionUI {
    if (-not $script:UiReady) { return }
    $busy=In-Progress
    if ($busy) {
        $label=$script:BusyAction.ToUpperInvariant()+' IN PROGRESS'
        $script:Ui.HeroState.Text=$label
        $script:Ui.HeroDescription.Text='Running a hidden background PowerShell worker. Routing safeguards remain controlled by the original engine.'
        $script:Ui.HeaderState.Text=$label
        $script:Ui.StatusDot.Fill=$script:Window.Resources['TT.Warning']
        Set-TrayArtwork 'connecting'
    } elseif (-not (Has-Session)) {
        $script:Ui.HeroState.Text='Disconnected'
        $script:Ui.HeroDescription.Text='No active VeylRoute session-state file. Connect to start the protected route.'
        $script:Ui.HeaderState.Text='DISCONNECTED'
        $script:Ui.StatusDot.Fill=$script:Window.Resources['TT.Muted']
        Clear-StatusCards
        Reset-VeylPrivacy
        $script:VerifiedThisSession=$false
        Set-TrayArtwork 'disconnected'
        $script:Ui.AutoRefreshNotice.Text='No active session. Auto-refresh starts after connecting.'
        $script:SessionKey=''
        $script:StatusCacheLoaded=$false
    } else {
        try {
            $state=Read-Json $script:StatePath
            if (-not $state) { throw 'Session-state file cannot be read.' }
            $nowKey=[string](Field $state 'StartedAt' '')
            if ($script:SessionKey -ne $nowKey) {
                $script:SessionKey=$nowKey
                $script:VerifiedThisSession=$false
                $script:AutoStatusLastStart=[datetime]::MinValue
                $script:AutoStatusInitialDue=(Get-Date).AddSeconds(3)
                $script:StatusCacheLoaded=$false
                Clear-StatusCards
                Load-StatusCache
            }
            $torActive=($state.TorPid -and (Get-Process -Id ([int]$state.TorPid) -ErrorAction SilentlyContinue))
            $tunActive=($state.TunPid -and (Get-Process -Id ([int]$state.TunPid) -ErrorAction SilentlyContinue))
            if ($torActive -and $tunActive) {
                $script:Ui.HeroState.Text=if ($script:VerifiedThisSession) { 'Connected - verified' } else { 'Session active - unverified' }
                $modeLabel=if([string]$state.RoutingMode -eq 'selectedappsonly'){'SelectedAppsOnly - system DNS is direct'}else{'SystemWide - default TCP via Tor'}
                $script:Ui.HeroDescription.Text="Tor and tun2socks processes detected | $modeLabel | Adapter: $($state.PhysicalAlias). Run Health Check for a fresh network probe."
                $script:Ui.HeaderState.Text=if ($script:VerifiedThisSession) { 'CONNECTED (TESTED)' } else { 'SESSION PRESENT' }
                $script:Ui.StatusDot.Fill=if ($script:VerifiedThisSession) { $script:Window.Resources['TT.Accent'] } else { $script:Window.Resources['TT.Warning'] }
                Set-TrayArtwork $(if ($script:VerifiedThisSession) { 'connected' } else { 'warning' })
            } else {
                $script:VerifiedThisSession=$false
                $script:Ui.HeroState.Text='Session degraded'
                $script:Ui.HeroDescription.Text='One or more managed processes are missing. Leave fail-closed routing intact; use Health, Disconnect or Recovery.'
                $script:Ui.HeaderState.Text='DEGRADED - CHECK'
                $script:Ui.StatusDot.Fill=$script:Window.Resources['TT.Warning']
                Set-TrayArtwork 'warning'
            }
        } catch {
            $script:VerifiedThisSession=$false
            $script:Ui.HeroState.Text='Session state needs attention'
            $script:Ui.HeroDescription.Text='Session state could not be inspected. Use Status or Recovery.'
            $script:Ui.HeaderState.Text='CHECK STATE'
            $script:Ui.StatusDot.Fill=$script:Window.Resources['TT.Warning']
            Set-TrayArtwork 'warning'
        }
    }
    $script:Ui.BtnStart.IsEnabled=(-not $busy -and -not (Has-Session))
    $script:Ui.BtnNewCircuit.IsEnabled=(-not $busy -and (Has-Session) -and $script:VerifiedThisSession)
    $script:Ui.BtnStop.IsEnabled=($(if($busy){($script:BusyAction -eq 'Start' -and -not $script:CancelRequested)}else{(Has-Session)}))
    $script:Ui.LblBtnStop.Text=if($busy -and $script:BusyAction -eq 'Start'){'Cancel connection'}else{'Disconnect'}
    $script:Ui.BtnRecover.IsEnabled=(-not $busy -and (Has-Session))
    $script:Ui.BtnRecoveryMaintenance.IsEnabled=(-not $busy -and (Has-Session))
    $script:Ui.BtnPreflight.IsEnabled=(-not $busy -and -not (Has-Session))
    $script:Ui.BtnPrivacyRecheck.IsEnabled=(-not $busy -and (Has-Session))
    $script:Ui.BtnCheckExits.IsEnabled=(-not $busy)
    foreach ($n in @('BtnStatus','BtnHealth','BtnUpdates')) { $script:Ui[$n].IsEnabled=-not $busy }
    $script:Ui.BtnSave.IsEnabled=(-not $busy -and -not (Has-Session))
    $script:Ui.BtnReload.IsEnabled=(-not $busy)
    $script:Ui.BtnTidy.IsEnabled=(-not $busy -and -not (Has-Session))
    $script:Ui.BtnUntidy.IsEnabled=(-not $busy -and -not (Has-Session))
    $script:Ui.BtnPrepareUpdate.IsEnabled=(-not $busy)
    $script:Ui.BtnInstallUpdate.IsEnabled=(-not $busy -and -not (Has-Session) -and (Test-Path -LiteralPath $script:VerifiedPackagePath))
    foreach($n in @('BtnProvisionHelpers','BtnImportComponents')){$script:Ui[$n].IsEnabled=(-not $busy -and -not (Has-Session))}
    $script:Ui.BtnInventory.IsEnabled=(-not $busy)
    # A fresh Tor installation has no previous version to restore, even though
    # it now correctly has an installation receipt. Never enable a false rollback.
    $rollbackPossible=$false
    try {
        if(Test-Path -LiteralPath $script:InstalledPackagePath -PathType Leaf){
            $rollbackRecord=Read-Json $script:InstalledPackagePath
            $backupLocation=[string]$rollbackRecord.originalDirectory
            $hasPrevious=$true
            if($rollbackRecord.PSObject.Properties.Name -contains 'rollbackAvailable'){
                $hasPrevious=[bool]$rollbackRecord.rollbackAvailable
            }
            $rollbackPossible=($hasPrevious -and -not [string]::IsNullOrWhiteSpace($backupLocation) -and
                (Test-Path -LiteralPath $backupLocation -PathType Container))
        }
    }catch { $rollbackPossible=$false }
    $script:Ui.BtnRollbackUpdate.IsEnabled=(-not $busy -and -not (Has-Session) -and $rollbackPossible)
    foreach ($n in @('BtnAddApp','BtnRemoveApp','BtnAddTorApp','BtnRemoveTorApp','BtnValidateBridges','BtnSelectVisible','BtnClearCountries')) { $script:Ui[$n].IsEnabled=(-not $busy -and -not (Has-Session)) }
    if ($script:TrayIcon) {
        $title='VeylRoute: '+[string]$script:Ui.HeaderState.Text
        if ($title.Length -gt 63) { $title=$title.Substring(0,63) }
        try { $script:TrayIcon.Text=$title } catch {}
    }
}
# Read while a worker owns the redirected stdout file. Do not truncate or mutate the raw log.
function Read-VeylSharedText([string]$Path) {
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return ''}
    $stream=$null;$reader=$null
    try{
        $stream=[IO.FileStream]::new($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true)
        return $reader.ReadToEnd()
    }finally{if($reader){$reader.Dispose()}elseif($stream){$stream.Dispose()}}
}
function Format-VeylActivity([string]$Raw) {
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($line in ($Raw -split '\r?\n')){
        if([string]::IsNullOrWhiteSpace($line)){ $lines.Add('');continue }
        $tag='INFO'
        if($line -match '(?i)START FAILED:|Worker error:|Verification error:|^\s*FAIL(?:ED|URE)?\b|\[err\]|-- Standard error --|\bResult:\s*[1-9]\d*'){ $tag='ERROR' }
        elseif($line -match '(?i)\bWARNING:|\[warn\]|\bATTENTION NEEDED\b|\bNOT READY\b'){ $tag='WARN' }
        elseif($line -match '(?i)\bBootstrapped\s+\d+%|\bTor bootstrap\s*:\s*\d+%|^\s*\[\d+/10\]|\bDownloading\b|\bExtracting\b'){ $tag='PROGRESS' }
        elseif($line -match '(?i)\bCONNECTED\b|\bHEALTHY\b|\bREADY FOR START\b|\bRollback succeeded\b'){ $tag='OK' }
        $lines.Add(('[{0,-8}] {1}' -f $tag,$line))
    }
    return ($lines -join "`r`n")
}
function Get-VeylActivitySource {
    $finished=Read-VeylSharedText $script:LastLog
    if(-not(In-Progress)){return $finished}
    $out=Read-VeylSharedText ($script:LastLog+'.out')
    $err=Read-VeylSharedText ($script:LastLog+'.err')
    $text=$finished
    if($out){$text+="`r`n"+$out}
    if($err){$text+="`r`n-- Standard error (live) --`r`n"+$err}
    return $text
}

function Update-Log {
    if([string]::IsNullOrWhiteSpace($script:LastLog) -or -not(Test-Path -LiteralPath $script:LastLog -PathType Leaf)){return}
    try{
        $files=@($script:LastLog)
        if(In-Progress){$files+=@($script:LastLog+'.out',$script:LastLog+'.err')}
        $parts=New-Object 'System.Collections.Generic.List[string]'
        foreach($path in $files){
            if(Test-Path -LiteralPath $path -PathType Leaf){
                $i=Get-Item -LiteralPath $path
                $parts.Add(([string]$i.LastWriteTimeUtc.Ticks+':'+[string]$i.Length))
            }
        }
        $stamp=$parts -join '|'
        if($stamp -eq $script:LastLogStamp){return}
        $raw=Get-VeylActivitySource
        $script:LastLogStamp=$stamp
        $script:CurrentDisplayLog=Format-VeylActivity $raw
        $wasAtBottom=($script:Ui.TxtLog.VerticalOffset -ge ($script:Ui.TxtLog.ExtentHeight-$script:Ui.TxtLog.ViewportHeight-4))
        $script:Ui.TxtLog.Text=$script:CurrentDisplayLog
        if($wasAtBottom -or $script:Ui.TxtLog.VerticalOffset -eq 0){$script:Ui.TxtLog.ScrollToEnd()}
        $script:Ui.LogHeader.Text='Latest: '+$(if($script:BusyAction){$script:BusyAction}else{'completed operation'})+' | '+[IO.Path]::GetFileName($script:LastLog)
        $e=@([regex]::Matches($raw,'(?im)^\s*(?:START FAILED:|Worker error:|Verification error:|ERROR:)')).Count
        $w=@([regex]::Matches($raw,'(?im)^\s*WARNING:')).Count
        $script:Ui.LogSeveritySummary.Text="Live output | errors $e | warnings $w | complete raw record retained in the log folder"
        if((In-Progress) -and $script:BusyAction -eq 'Start'){
            $progress=[regex]::Matches($raw,'(?im)^\s*Tor bootstrap\s*:\s*(\d+)%')
            if($progress.Count -gt 0){
                $pc=[int]$progress[$progress.Count-1].Groups[1].Value
                $script:LiveBootstrap=$pc
                $script:Ui.DashboardLastAction.Text="Connecting to Tor: $pc% bootstrap. Disconnect is available as a safe Cancel request."
                $script:Ui.HeroDescription.Text="Tor bootstrap $pc%. Connection not yet verified; cancel will request safe rollback."
            }else{$script:Ui.DashboardLastAction.Text='Connect started; waiting for Tor bootstrap. You can cancel before it completes.'}
        }
    }catch{Set-Footer 'Activity stream temporarily unavailable; the worker is still running.'}
}
function Refresh-VersionCards {
    $r=$null
    try { $r=Read-Json $script:VersionsPath } catch {}
    if (-not $r) {
        $script:Ui.InstalledTor.Text='--';$script:Ui.LatestTor.Text='--';$script:Ui.LatestBundle.Text='--'
        $script:Ui.UpdateSummary.Text='No update check performed'
        $script:Ui.UpdateNotes.Text='Select Check for updates to query the official Tor release information. No binaries are changed.'
        Refresh-UpdateStage
        return
    }
    $script:Ui.InstalledTor.Text=if ($r.installedTor) {[string]$r.installedTor} else {'Not detected'}
    $script:Ui.LatestTor.Text=if ($r.latestCore) {[string]$r.latestCore} else {'Unverified'}
    $script:Ui.LatestBundle.Text=if ($r.latestWindowsExpertCore) {[string]$r.latestWindowsExpertCore} elseif ($r.latestWindowsExpertRelease) {[string]$r.latestWindowsExpertRelease+' (bundle release)'} else {'Unverified'}
    $script:Ui.UpdateSummary.Text=switch ([string]$r.checkState) {
        'UpdateAvailable' {'An update may be available'}
        'UpToDate' {'Core Tor release check passed'}
        default {'Unable to confirm current version'}
    }
    $script:Ui.UpdateNotes.Text='Checked '+[string]$r.checkedAt+' | '+[string]$r.details
    Refresh-UpdateStage
}
function Request-VeylStartCancellation {
    if(-not(In-Progress) -or $script:BusyAction -ne 'Start' -or -not $script:CancelFile){return}
    if($script:CancelRequested){return}
    [IO.File]::WriteAllText($script:CancelFile,((Get-Date).ToString('o')+' cancel requested'),$script:Utf8)
    $script:CancelRequested=$true
    $script:Ui.DashboardLastAction.Text='Cancellation requested. Waiting for the Start engine to finish safe rollback...'
    Set-Footer 'Cancel requested; do not kill PowerShell while routes are being restored.'
    Update-SessionUI
}
function Run-Action([string]$Action,[bool]$Automatic=$false) {
    if (In-Progress) { throw 'A background operation is already running.' }
    if (-not (Test-Path -LiteralPath $script:WorkerPath -PathType Leaf)) { throw 'Missing TorTunnel.GuiWorker.ps1 from the current installation.' }
    if ($Action -in @('Start','Preflight','Tidy','Untidy','UpdateInstall','UpdateRollback','ProvisionHelpers','ImportComponents') -and (Has-Session)) { throw 'An active session-state file exists. Stop or recover first.' }
    if (-not (Test-Path -LiteralPath $script:LogDir)) { [void](New-Item -ItemType Directory -Path $script:LogDir -Force) }
    $script:BusyAutomatic=$Automatic
    $script:BusyAction=$Action
    $script:Ui.DashboardLastAction.Text="$Action started at $(Get-Date -Format HH:mm:ss). Progress will appear here and in Activity."
    if($Action -eq 'Start'){
        $script:LiveBootstrap=-1
        $script:CancelRequested=$false
        $script:CancelFile=Join-Path $script:LogDir ('start-cancel-'+[guid]::NewGuid().ToString('N')+'.flag')
        Set-VeylPrivacyPending
    }
    if($Action -in @('ProvisionHelpers','ImportComponents','UpdatePrepare','UpdateInstall','UpdateRollback')){
        $script:TransferVisibleAction=$Action
        $script:TransferStartedUtc=[datetime]::UtcNow
        $script:Ui.TransferPanel.Visibility=[System.Windows.Visibility]::Visible
        $script:Ui.TransferStatus.Text='WORKING'
        $script:Ui.TransferStage.Text='Starting '+$Action+'...'
        $script:Ui.TransferDescription.Text='Waiting for the background worker to report actual transfer or extraction progress.'
        $script:Ui.TransferBytes.Text='Waiting for transfer'
        $script:Ui.TransferLocation.Text='No destination written yet.'
        $script:Ui.TransferProgress.IsIndeterminate=$true
        $script:Ui.TransferProgress.Value=0
    }
    $script:LastLog=Join-Path $script:LogDir ((Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+$Action.ToLowerInvariant()+'.log')
    $script:LastLogStamp=''
    $script:Ui.TxtLog.Text='Operation starting: '+$Action+' ...' 
    $modeArg=if($script:Ui.CmbRouteMode.SelectedIndex -eq 1){'SelectedAppsOnly'}else{'SystemWide'}
    $workerArguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$script:WorkerPath+'" -Action '+$Action+' -Root "'+$script:Root+'" -LogPath "'+$script:LastLog+'" -RoutingMode '+$modeArg
    if($Action -eq 'Start'){$workerArguments+=' -CancelFile "'+$script:CancelFile+'"'}
    if($Action -eq 'UpdatePrepare' -and $script:PendingSignedImportDirectory){
        if($script:PendingSignedImportDirectory.Contains('"')){throw 'Import folder path contains an unsupported quotation mark.'}
        $workerArguments+=' -SourceDirectory "'+$script:PendingSignedImportDirectory+'"'
    }
    if($Action -eq 'ImportComponents'){
        if(-not $script:PendingImportDirectory){throw 'Select a source folder containing the binaries.'}
        if($script:PendingImportDirectory.Contains('"')){throw 'Folder path contains an unsupported quotation mark.'}
        $workerArguments+=' -SourceDirectory "'+$script:PendingImportDirectory+'"'
    }
    $start=New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName=$script:PowerShellExe
    $start.Arguments=$workerArguments
    $start.WorkingDirectory=$script:Root
    $start.CreateNoWindow=$true
    $start.UseShellExecute=$false
    $start.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $proc=New-Object System.Diagnostics.Process
    $proc.StartInfo=$start
    if (-not $proc.Start()) { throw "Could not start hidden $Action worker." }
    $script:BusyProc=$proc
    Set-Footer "$Action started. Progress is visible on Overview and in Activity."
    Update-SessionUI
}

# The engine remains authoritative; this UI does not alter network safeguards.
# These recognizers translate confirmed engine/log outcomes into human instructions.
function Get-VeylIssue {
    param([string]$Action,[string]$Text,[int]$ExitCode=1)
    $message=if($Text){[string]$Text}else{'The operation did not provide an error message.'}
    $issue=[ordered]@{
        Title=($Action+' needs attention')
        Summary='VeylRoute could not complete the requested operation.'
        Solution='Try again once. If the problem continues, review the optional technical details or open the Activity page. Do not disable network or DNS protections to work around it.'
        ActionLabel=''
        ActionKey=''
        Details=''
        Severity='Error'
    }
    $clean=[regex]::Replace($message,'(?im)(?:Bridge\s+)?obfs4\s+(?:\d{1,3}\.){3}\d{1,3}:\d+[^\r\n]*','[obfs4 bridge line hidden]')
    $clean=[regex]::Replace($clean,'(?im)^(.*\bcert=)[^\s]+','$1[hidden]')
    $clean=[regex]::Replace($clean,'(?im)^(.*\biat-mode=)\d+','$1[hidden]')
    if($clean.Length -gt 7000){$clean=$clean.Substring(0,2400)+"`r`n...`r`n"+$clean.Substring($clean.Length-3600)}
    $issue.Details=$clean
    $missing=New-Object 'System.Collections.Generic.List[string]'
    $portables=[regex]::Match($message,'(?im)Required portable component\(s\) missing:\s*([^\r\n]+)')
    $inventory=[regex]::Matches($message,'(?im)^\s*(Tor|lyrebird|GeoIP6?|tun2socks|Wintun)\s*:\s*MISSING\s*$')
    if($portables.Success -or $inventory.Count -gt 0){
        $source=if($portables.Success){$portables.Groups[1].Value}else{''}
        if($source -match '(?i)tor\\tor|tor\.exe|Tor executable' -or $message -match '(?im)^\s*Tor\s*:\s*MISSING'){$missing.Add('Tor client')}
        if($source -match '(?i)lyrebird\.exe' -or $message -match '(?im)^\s*lyrebird\s*:\s*MISSING'){$missing.Add('obfs4 transport (lyrebird)')}
        if($source -match '(?i)geoip6' -or $message -match '(?im)^\s*GeoIP6\s*:\s*MISSING'){$missing.Add('GeoIP6 data')}
        if(($source -match '(?i)\bgeoip\b' -or $message -match '(?im)^\s*GeoIP\s*:\s*MISSING') -and -not $missing.Contains('GeoIP data')){$missing.Add('GeoIP data')}
        if($source -match '(?i)tun2socks\.exe' -or $message -match '(?im)^\s*tun2socks\s*:\s*MISSING'){$missing.Add('tun2socks')}
        if($source -match '(?i)wintun\.dll' -or $message -match '(?im)^\s*Wintun\s*:\s*MISSING'){$missing.Add('Wintun')}
        $issue.Title='Required components are missing'
        $issue.Summary=if($missing.Count){'The following components are not installed: '+($missing -join ', ')+'.'}else{'One or more required portable binaries or data files are missing.'}
        $issue.Solution='Open Versions & updates. Download Wintun + tun2socks if either is missing. For Tor, lyrebird or GeoIP, use Download + verify signature, then Install verified update. You can also import an existing trusted binary set. Run Preflight again afterward.'
        $issue.ActionLabel='Open component setup';$issue.ActionKey='Updates'
    } elseif($message -match '(?i)no obfs4 bridges|bridge line|bridges\.txt|bridge configuration|unsupported bridge'){
        $issue.Title='obfs4 bridges need attention'
        $issue.Summary='The bridge configuration is missing or could not be accepted.'
        $issue.Solution='Open obfs4 bridges. Choose Get obfs4 bridges to request lines from the official Tor Project service, paste them, Validate format, and Save configuration. Keep the complete fingerprint and certificate text.'
        $issue.ActionLabel='Open bridge setup';$issue.ActionKey='Bridges'
    } elseif($message -match '(?i)No TOR apps configured|TOR.only app|SelectedAppsOnly.*(?:not ready|failed)|selected apps.*missing'){
        $issue.Title='Selected-app routing needs configuration'
        $issue.Summary='The selected-app mode is not ready to route an application through Tor.'
        $issue.Solution='Open Application routing, add one or more TOR-only executables, keep the direct-egress and UDP blocks enabled, and Save configuration. Or choose System-wide Tor if that mode is ready.'
        $issue.ActionLabel='Open application routing';$issue.ActionKey='Apps'
    } elseif($message -match '(?i)DNS.over.HTTPS|strict DoH|DoH resolver|DohTemplate|DNS.*(?:unavailable|failed|rejected)|resolver'){
        $issue.Title='Secure DNS needs attention'
        $issue.Summary='The configured DNS protection could not be applied or verified.'
        $issue.Solution='Open DNS protection and check the provider addresses and HTTPS endpoint. Strict DNS protection must remain enabled for System-wide mode; if Windows lacks required DoH support, the connection must not silently fall back to plaintext DNS.'
        $issue.ActionLabel='Open DNS settings';$issue.ActionKey='Dns'
    } elseif($Action -eq 'ExitAvailability'){
        $issue.Title='Cannot verify available Tor exits'
        $issue.Summary='The Tor Project relay-data request did not return a usable, fresh snapshot.'
        $issue.Solution='Check connectivity and try Refresh Tor exit availability later. An unverified country is not a confirmed available exit. VeylRoute will not silently change the selected country.'
        $issue.ActionLabel='Open exit settings';$issue.ActionKey='Countries'
    } elseif($message -match '(?i)ExitCountr|country allow.list|selected country|exit selection'){
        $issue.Title='Exit-country configuration needs attention'
        $issue.Summary='The requested Tor exit-country setting could not be used or verified.'
        $issue.Solution='Open Exit locations, review the chosen country and allow-list, and Save configuration. An exit-country verification failure must not be treated as a successful verified connection.'
        $issue.ActionLabel='Open exit settings';$issue.ActionKey='Countries'
    } elseif($message -match '(?i)OpenClipboard Failed|0x800401D0|CLIPBRD_E_CANT_OPEN|clipboard.+(?:locked|busy|in use)'){
        $issue.Title='Windows clipboard is busy'
        $issue.Summary='Another application is temporarily using the clipboard, so the copy or paste request could not finish.'
        $issue.Solution='Close any active clipboard manager or remote-desktop clipboard operation and try again. You can still select and copy text manually; VeylRoute remains open.'
    } elseif($message -match '(?i)SHA256 mismatch|signature.*(?:fail|invalid|unavailable)|OpenPGP|signing key|not validated|verification failed'){
        $issue.Title='Binary verification did not pass'
        $issue.Summary='VeylRoute did not verify the downloaded binary package or its signing information.'
        $issue.Solution='Open Versions & updates and try Download + verify signature again using the official source. Installation must remain blocked until verification succeeds. Do not bypass this security check.'
        $issue.ActionLabel='Open updates';$issue.ActionKey='Updates'
    } elseif($message -match '(?i)session.state|legacy tunnel.state|manual tun2socks|old/manual|/1 routes|rollback.*(?:incomplete|failed)|stale session'){
        $issue.Title='Existing network session needs recovery'
        $issue.Summary='An existing or interrupted routing session needs to be resolved before another connection can start.'
        $issue.Solution='Open Overview and use Disconnect or Recovery/rollback. Do not manually delete session-state files or networking rules; the recovery script needs them to restore Windows settings.'
        $issue.ActionLabel='Open recovery controls';$issue.ActionKey='Dashboard'
    } elseif($message -match '(?i)port\s+\d+.*in use|ports? free'){
        $issue.Title='A required local port is already in use'
        $issue.Summary='Another process is using a network port needed by VeylRoute.'
        $issue.Solution='Close the conflicting application or choose a different available SOCKS port in Advanced settings, then save and repeat Preflight. Do not disable firewall protection.'
        $issue.ActionLabel='Open advanced settings';$issue.ActionKey='Security'
    } elseif($message -match '(?i)Tor did not reach 100%|Tor exited|SOCKS.*(?:failed|did not)|Tor.*bootstrap|bridge.*unreachable|pluggable transport'){
        $issue.Title='Tor could not establish a usable circuit'
        $issue.Summary='Tor or its obfs4 transport did not reach a verified working connection.'
        $issue.Solution='At 45% Tor is requesting relay descriptors. This does not prove the selected exit country has no relays. Refresh exit availability, review the bridges and try an available exit. Do not disable leak protection. If session state remains, use Disconnect/Recovery.'
        $issue.ActionLabel='Review bridge setup';$issue.ActionKey='Bridges'
    } elseif($message -match '(?i)Internet.*(?:adapter|route)|Wi.Fi|Ethernet.*(?:missing|not connected)|No active IPv4'){
        $issue.Title='No usable Internet connection was detected'
        $issue.Summary='VeylRoute could not identify the physical network connection required for routing.'
        $issue.Solution='Connect Windows to Wi-Fi or Ethernet first. Check that the adapter has a usable IPv4 default route, then repeat Preflight.'
    } elseif($message -match '(?i)UnauthorizedAccess|access is denied|administrator|elevat|permission'){
        $issue.Title='Windows permission is required'
        $issue.Summary='A Windows operation was blocked by permissions or elevation.'
        $issue.Solution='Exit the controller and launch VeylRoute.vbs as administrator, then repeat the action. Do not loosen security policies or file permissions broadly.'
    } elseif($message -match '(?i)WinDivert|Wintun.*(?:fail|exit)|tun2socks.*(?:fail|exit)|network adapter.*(?:fail|missing)'){
        $issue.Title='Virtual network adapter needs attention'
        $issue.Summary='The Wintun/tun2socks network layer could not start or stay available.'
        $issue.Solution='Open Versions & updates and verify the helper binaries. If they are present, try Disconnect/Recovery, then repeat Preflight. Do not remove active network routes by hand.'
        $issue.ActionLabel='Open components';$issue.ActionKey='Updates'
    } elseif($message -match '(?i)Unable to download|download.*(?:failed|timed out)|web request|TLS|network.*unreachable'){
        $issue.Title='Component download could not finish'
        $issue.Summary='The requested file could not be downloaded or contacted at its source.'
        $issue.Solution='Check your normal Internet connection and retry from Versions & updates. Existing binaries have not been replaced by an unverified download.'
        $issue.ActionLabel='Open updates';$issue.ActionKey='Updates'
    } elseif($message -match '(?i)GUI worker is missing|TorTunnel.GuiWorker.ps1|Missing WPF layout|settings.json.*missing|Missing config\\settings.json'){
        $issue.Title='VeylRoute installation is incomplete'
        $issue.Summary='One or more required application files are missing or cannot be read.'
        $issue.Solution='Close VeylRoute and re-extract the complete ZIP to a writable local folder. Do not mix files from different versions or overwrite an active tunnel. Preserve your existing config and runtime folders before replacing anything.'
    } elseif($message -match '(?i)Windows.*(?:unsupported|required|not supported)|ARM64|32.bit'){
        $issue.Title='Windows compatibility needs attention'
        $issue.Summary='The installed Windows version or system architecture does not meet this operation''s prerequisites.'
        $issue.Solution='Use compatible Windows x64 components, and ensure Windows supports the required routing and DNS features. Do not force an incompatible binary installation.'
    } else {
        $match=[regex]::Match($message,'(?im)^\s*(?:START FAILED:|Worker error:|RESULT\s+:\s*NOT READY\s*-|Error:)\s*(.+)$')
        if($match.Success){
            $issue.Summary=$match.Groups[1].Value.Trim()
        }elseif($message.Length -lt 330){
            $issue.Summary=$message.Trim()
        }elseif($Action -eq 'Preflight'){
            $issue.Summary='The readiness check found a problem that prevents a safe start.'
            $issue.Solution='Correct the reported requirement before connecting. Technical details are available below if the cause is not clear.'
        }
    }
    return [pscustomobject]$issue
}
function Get-VeylOperationIssue {
    param([string]$Action,[int]$ExitCode,[string]$Log,[object]$Result)
    $raw=if($Log){[string]$Log}else{''}
    $detail=if($Result -and $Result.PSObject.Properties['detail']){[string]$Result.detail}else{''}
    $notReady=($raw -match '(?im)^\s*RESULT\s+:\s*NOT READY')
    $startFailed=($raw -match '(?im)^\s*START FAILED:')
    if($Action -in @('ProvisionHelpers','ImportComponents','UpdatePrepare','UpdateInstall','UpdateRollback') -and $ExitCode -ne 0){
        try{
            $transfer=Read-Json $script:TransferProgressPath
            if($transfer -and [string]$transfer.action -eq $Action -and [string]$transfer.state -eq 'Failed'){
                $issue=Get-VeylIssue -Action $Action -Text ([string]$transfer.detail) -ExitCode $ExitCode
                $issue.Title='Component setup failed: '+[string]$transfer.stage
                $reason=[string]$transfer.detail
                $issue.Summary=if($reason.Length -gt 340){$reason.Substring(0,340)+'...'}else{$reason}
                $issue.Details=$reason+"`r`n`r`n"+$raw
                $issue.Solution='The component operation stopped before installation could be verified. Use the specific cause above to correct the problem; the binary safety checks remain enforced.'
                if($reason -match '(?i)(?:tor|tun2socks|lyrebird) process is running'){
                    $issue.Solution='Another Tor-related process is running. Disconnect and exit the older TorTunnel/VeylRoute controller normally, then retry. Do not delete binaries or force-close an active tunnel.'
                }elseif($reason -match '(?i)(?:clipboard|permission denied|access is denied|unauthorized)'){
                    $issue.Solution='Check access to the current portable folder. Use a writable local directory and rerun VeylRoute with its normal elevation prompt.'
                }elseif($reason -match '(?i)(?:SSL|TLS|certificate|connection|timed out|name resolution|remote name|could not be resolved|host)'){
                    $issue.Solution='The official HTTPS source could not be reached or resolved. For signed Tor bundles, try Import signed bundle with the original Windows Expert Bundle and matching .asc signature from a trusted source. No unverified binary will be installed.'
                }elseif($reason -match '(?i)(?:SHA256|checksum|signature|signed)'){
                    $issue.Solution='The downloaded component did not pass a required verification. Do not install it; a new verified download is required.'
                }
                $issue.ActionKey='Updates';$issue.ActionLabel='Open components'
                return $issue
            }
        }catch{}
    }
    if($Action -eq 'UpdatePrepare'){
        try{
            $stage=Read-Json $script:PrepareStagePath
            if($stage -and [string]$stage.action -eq 'Prepare' -and [string]$stage.status -eq 'Failed'){
                $problem=[string]$stage.detail
                $issue=Get-VeylIssue -Action 'Signed update' -Text ($problem+"`r`n"+$raw) -ExitCode 1
                $issue.Title='Update stopped: '+[string]$stage.stage
                $issue.Summary=if($problem.Length -gt 260){$problem.Substring(0,260)+'...'}else{$problem}
                if(-not $issue.ActionKey){
                    $issue.ActionKey='Updates';$issue.ActionLabel='Open component setup'
                    $issue.Solution='Check your Internet connection and Windows compatibility. The current binaries were not replaced. Repeating the same download will not help until the reported stage is corrected.'
                }
                return $issue
            }
        }catch{}
    }
    if($Action -eq 'Inventory'){
        if($raw -match '(?im)^\s*(?:Tor|lyrebird|GeoIP6?|tun2socks|Wintun)\s*:\s*MISSING\s*$'){
            return Get-VeylIssue -Action 'Component inventory' -Text $raw -ExitCode 1
        }
    }
    if($Action -eq 'Preflight'){
        # Preflight may consider the other routing mode ready while the mode selected in the UI is not.
        $mode=if($script:Ui.CmbRouteMode.SelectedIndex -eq 1){'SelectedAppsOnly'}else{'SystemWide'}
        $pattern='(?im)^\s*'+[regex]::Escape($mode)+'\s*:\s*(.+)$'
        $modeResult=[regex]::Match($raw,$pattern)
        if($modeResult.Success -and $modeResult.Groups[1].Value.Trim() -ne 'READY'){
            $reason=$modeResult.Groups[1].Value.Trim()
            $issue=Get-VeylIssue -Action 'Preflight' -Text ($mode+' is not ready: '+$reason) -ExitCode 1
            $issue.Title='Selected routing mode is not ready'
            if($issue.Summary -eq 'VeylRoute could not complete the requested operation.'){$issue.Summary=$mode+' is not ready: '+$reason}
            return $issue
        }
    }
    if($Action -eq 'Start' -and $ExitCode -eq 0 -and -not(Has-Session)){
        $issue=Get-VeylIssue -Action 'Connect' -Text 'The worker reported completion, but no active session-state file was found.' -ExitCode 1
        $issue.Title='Connection not verified'
        $issue.Summary='No active session state exists. The GUI cannot confirm that the tunnel is connected.'
        $issue.Solution='Do not assume traffic is protected. Review the connection log, repeat Preflight, and reconnect only after the problem is resolved.'
        return $issue
    }
    if($Action -in @('Stop','Recover') -and $ExitCode -eq 0 -and (Has-Session)){
        $issue=Get-VeylIssue -Action $Action -Text 'Session state still exists after Stop/Recovery.' -ExitCode 1
        $issue.Title='Network restoration not confirmed'
        $issue.Summary='The Stop/Recovery worker returned, but VeylRoute still detects an active session-state file.'
        $issue.Solution='Do not delete session files or networking rules manually. Use controlled Recovery and verify that Windows networking is restored.'
        return $issue
    }
    if($Action -in @('Status','Health') -and $ExitCode -eq 0){
        $overall=[regex]::Match($raw,'(?im)^\s*Overall\s*:\s*([^\r\n]+)')
        if((Has-Session) -and -not $overall.Success){
            $issue=Get-VeylIssue -Action $Action -Text 'No complete status result was returned for the active session.' -ExitCode 1
            $issue.Title='Protection checks incomplete'
            $issue.Summary='The session exists, but the status worker did not produce an Overall health result.'
            $issue.Solution='Do not treat the session as verified. Retry Health and inspect Activity. Disconnect safely if protection cannot be confirmed.'
            return $issue
        }
        if($overall.Success -and $overall.Groups[1].Value.Trim() -notmatch '^HEALTHY'){
            $issue=Get-VeylIssue -Action $Action -Text ('Health result: '+$overall.Groups[1].Value.Trim()) -ExitCode 1
            $issue.Title='Connection health needs attention'
            $issue.Summary='The latest network verification did not report a healthy connection: '+$overall.Groups[1].Value.Trim()
            $issue.Solution='Review the connection state on Overview. If any protection or route is degraded, use Disconnect/Recovery before another connection attempt. Do not treat the connection as verified.'
            $issue.ActionLabel='Open connection controls';$issue.ActionKey='Dashboard'
            return $issue
        }
    }
    if($ExitCode -eq 0 -and -not $notReady -and -not $startFailed){
        # Worker exit codes alone do not prove that a security-sensitive check succeeded.
        if($Action -eq 'Preflight' -and $raw -notmatch '(?im)^\s*RESULT\s+:\s*READY FOR START'){
            $unknown=Get-VeylIssue -Action 'Preflight' -Text 'Preflight did not produce the expected READY FOR START confirmation.'
            $unknown.Title='Readiness could not be confirmed'
            $unknown.Summary='VeylRoute could not confirm that Preflight completed all required checks.'
            $unknown.Solution='Repeat Preflight. If it still has no readiness result, use the optional technical details to report the failure. Do not connect until the selected mode passes.'
            return $unknown
        }
        if($Action -eq 'Start' -and $raw -notmatch '\[10/10\] CONNECTED'){
            $unknown=Get-VeylIssue -Action 'Connect' -Text 'Start ended without its [10/10] CONNECTED result.'
            $unknown.Title='Connection not verified'
            $unknown.Summary='The Start process exited, but did not confirm that the protected connection was established.'
            $unknown.Solution='Do not assume traffic is protected. If a session remains active, use Disconnect or Recovery, then repeat Preflight and Connect. Keep the fail-closed controls enabled.'
            $unknown.ActionLabel='Open connection controls';$unknown.ActionKey='Dashboard'
            return $unknown
        }
        if($Action -eq 'UpdatePrepare' -and -not (Test-Path -LiteralPath $script:VerifiedPackagePath -PathType Leaf)){
            $unknown=Get-VeylIssue -Action 'Signed update' -Text 'Update worker returned without creating a verified update record.'
            $unknown.Title='Download verification was not confirmed'
            $unknown.Summary='The update has not produced a verified installation candidate.'
            $unknown.Solution='Open Versions & updates and run Download + verify signature again. Do not install an unverified package.'
            $unknown.ActionLabel='Open updates';$unknown.ActionKey='Updates'
            return $unknown
        }
        # Warnings remain visible in the GUI, except a transient probe retry resolved by a verified start.
        $warnings=@([regex]::Matches($raw,'(?im)^\s*WARNING:\s*([^\r\n]+)') | ForEach-Object { $_.Groups[1].Value.Trim() })
        $warnings=@($warnings | Where-Object {
            $_ -and -not ($Action -eq 'Start' -and $raw.Contains('[10/10] CONNECTED') -and $_ -match 'probe.*retry')
        })
        if($warnings.Count -gt 0){
            $warningIssue=Get-VeylIssue -Action $Action -Text ($warnings -join "`r`n")
            $warningIssue.Title='Operation completed with a warning'
            $warningIssue.Summary=$warnings[0]
            $warningIssue.Severity='Warning'
            if(-not $warningIssue.ActionKey){$warningIssue.Solution='The operation finished, but the warning above may affect a protection or optional feature. Review the guidance and correct the condition before relying on that feature.'}
            return $warningIssue
        }
        return $null
    }
    $full=if($detail){$detail+"`r`n"+$raw}else{$raw}
    $issue=Get-VeylIssue -Action $Action -Text $full -ExitCode $ExitCode
    if($notReady){$issue.Title='Preflight found a problem';if($issue.Summary -match '^VeylRoute could not'){$issue.Summary='The readiness check found a condition that must be resolved before connecting.'}}
    if($Action -eq 'UpdatePrepare' -and $issue.Title -match 'needs attention'){$issue.Title='Signed update preparation failed'}
    return $issue
}
function Invoke-VeylIssueAction([string]$ActionKey) {
    if($ActionKey -in @('Updates','Bridges','Apps','Dns','Countries','Dashboard','Security','Maintenance','Activity')){
        Show-Page $ActionKey
    }
}
function Present-VeylIssue {
    param($Issue,[bool]$Automatic=$false)
    if(-not $Issue){return}
    $signature=[string]$Issue.Title+'|'+[string]$Issue.Summary
    if($Automatic -and $script:LastAutomaticIssueSignature -eq $signature){return}
    if($Automatic){$script:LastAutomaticIssueSignature=$signature}
    if($script:Window -and -not $script:Window.IsVisible){
        $script:PendingIssue=$Issue
        if($script:TrayIcon){
            try{
                $script:TrayIcon.BalloonTipTitle='VeylRoute: '+[string]$Issue.Title
                $script:TrayIcon.BalloonTipText=[string]$Issue.Summary
                $script:TrayIcon.BalloonTipIcon=[System.Windows.Forms.ToolTipIcon]::Warning
                $script:TrayIcon.ShowBalloonTip(3500)
            }catch{}
        }
        return
    }
    $kind=if($Issue.Severity -eq 'Warning'){
        [System.Windows.MessageBoxImage]::Warning
    }else{[System.Windows.MessageBoxImage]::Error}
    $pressed=Show-TTDialog -Title ([string]$Issue.Title) -Text ([string]$Issue.Summary) -Icon $kind -Solution ([string]$Issue.Solution) -ActionLabel ([string]$Issue.ActionLabel) -ActionKey ([string]$Issue.ActionKey) -Details ([string]$Issue.Details)
    if($pressed -and $Issue.ActionKey){Invoke-VeylIssueAction ([string]$Issue.ActionKey)}
}

function Show-VeylOperationSummary([string]$Action,[string]$Raw) {
    if(-not $script:Window.IsVisible){return}
    $d=Read-StatusFields $Raw
    $title=$Action+' complete'
    $message='The requested operation completed. Open Activity for the detailed record.'
    $advice='All technical details remain available under Activity and diagnostics.'
    switch($Action){
        'Start' {
            $title='Connected to Tor'
            $ip=[string]$d['tor exit ip'];if(-not $ip){$ip=[string]$d['exit ip']}
            $country=([string]$d['reported country']).Split(' ')[0]
            $message='Tor connection established.'+$(if($ip){"`r`nExit IP: $ip"}else{''})+$(if($country){"`r`nExit country: $country"}else{''})
            $advice='Automatic protection checks are starting. Overview will show verified controls and any unverified leak risks.'
        }
        'NewCircuit' {
            $title='New Tor circuit request'
            $before=[regex]::Match($Raw,'(?im)^Previous exit IP:\s*([^\r\n]+)')
            $after=[regex]::Match($Raw,'(?im)^Fresh exit IP\s*:\s*([^\r\n]+)')
            $change=[regex]::Match($Raw,'(?im)^Exit IP changed\s*:\s*([^\r\n]+)')
            $message='Tor acknowledged a NEWNYM request for future connections.'+$(if($before.Success){"`r`nPrevious IP: "+$before.Groups[1].Value.Trim()}else{''})+$(if($after.Success){"`r`nFresh IP: "+$after.Groups[1].Value.Trim()}else{''})
            if($change.Success){$message+="`r`nIP changed: "+$change.Groups[1].Value.Trim()}
            $advice='Tor may reuse the same exit or rate-limit circuit changes. Existing connections keep their established circuits; the selected country stays unchanged.'
        }
        'Stop' { $title='Disconnected';$message='The Stop script completed. Session state: '+$(if(Has-Session){'still present - verify recovery'}else{'disconnected'});$advice='Restart Edge if it was open so the restored QUIC policy takes effect. Verify ordinary browsing after disconnect.' }
        'Recover' { $title='Recovery completed';$message='The recovery command returned without a reported error.';$advice='Confirm original network connectivity and that no session-state file remains.' }
        'Status' {
            $title='Connection status';
            if(-not(Has-Session)){$message='VeylRoute is disconnected. No Tor session is active.'}
            else{$message='Connection: '+[string]$d['overall']+"`r`nTor exit: "+[string]$d['exit ip']+"`r`nCountry: "+[string]$d['country']}
            $advice='Privacy controls are shown at a glance on Overview. Complete raw checks are available in Activity.'
        }
        'Health' { $title='Health check';$message='Health: '+[string]$d['overall']+$(if($d['exit ip']){"`r`nTor exit: "+[string]$d['exit ip']}else{''});$advice='Local DNS safeguards do not prove an external DNS leak test. See Overview for the evidence limits and remedies.' }
        'Preflight' { $title='Preflight ready';$message='The selected routing mode passed readiness checks. It is ready to attempt a connection.';$advice='Preflight does not establish a Tor circuit or prove network privacy.' }
        'Updates' { $title='Update check complete';$message='The component version check finished.';$advice='Review the current and latest version values on Versions & updates.' }
        'ExitAvailability' { $title='Tor exit information refreshed';$message='The current running exit-relay data was retrieved from the Tor Project.';$advice='Exit flag and country describe the published relay list, not guaranteed website reachability.' }
        'Inventory' { $title='Component check complete';$message='The local component inventory finished.';$advice='Check component badges on Versions & updates for missing files.' }
        'UpdatePrepare' {$title='Signed update prepared';$message='The new Tor package was downloaded or imported and verified.';$advice='The installed binaries were not replaced. Review the verified package before choosing Install.'}
        'UpdateInstall' {$title='Tor component installed';$message='The worker reports a new verified Tor installation receipt.';$advice='Confirm the installed version and run Preflight before reconnecting.'}
        'UpdateRollback' {$title='Tor binaries restored';$message='The previous verified package was restored.';$advice='Run Preflight before connecting.'}
        'ImportComponents' {$title='Components imported';$message='The selected components were imported.';$advice='Imported components were trusted by you, not automatically signature-verified.'}
        'ProvisionHelpers' {$title='Helper installation completed';$message='Verified helper-binary installation finished.';$advice='Run Preflight before starting a new connection.'}
        'Tidy' {$title='Explorer declutter complete';$message='Visibility settings for support files were updated.';$advice='Files were not moved or deleted.'}
        'Untidy' {$title='Explorer visibility restored';$message='Support-file visibility settings were restored.';$advice='Files remain in their original locations.'}
    }
    [void](Show-TTDialog -Title $title -Text $message -Solution $advice -Details $Raw)
}

function Finish-Action {
    if ($null -eq $script:BusyProc -or -not $script:BusyProc.HasExited) { return }
    $code=[int]$script:BusyProc.ExitCode
    $done=$script:BusyAction
    $script:BusyProc.Dispose();$script:BusyProc=$null
    Update-Log
    $wasAutomatic=$script:BusyAutomatic
    $script:BusyAutomatic=$false
    $script:BusyAction=''
    $result=$null
    try { $result=Read-Json (Join-Path $script:LogDir 'last-result.json') } catch {}
    $recovery=''
    if($result -and [string]$result.action -eq $done -and [string]$result.logPath -eq $script:LastLog){
        $recovery=[string]$result.recovery
    }else{$result=$null}
    if ($done -in @('Stop','Recover')) { $script:VerifiedThisSession=$false }
    elseif ($code -ne 0 -and $done -in @('Start','Status','Health')) { $script:VerifiedThisSession=$false }
    elseif ($code -eq 0 -and (Has-Session) -and $done -in @('Start','Status','Health')) {
        $raw=Read-Text $script:LastLog
        if (($done -eq 'Start' -and $raw.Contains('[10/10] CONNECTED')) -or
            ($done -in @('Status','Health') -and ($raw -match '(?m)^Overall\s*:\s*HEALTHY'))) {
            $script:VerifiedThisSession=$true
        }
    }
    $completedLog=Read-Text $script:LastLog
    $issue=Get-VeylOperationIssue -Action $done -ExitCode $code -Log $completedLog -Result $result
    if($done -eq 'Start' -and $script:CancelRequested -and
       $completedLog -match '(?i)Connection cancelled by user request' -and -not(Has-Session)){
        $issue=Get-VeylIssue -Action 'Connect' -Text 'The connection attempt was cancelled and no session state remains.' -ExitCode 1
        $issue.Title='Connection cancelled'
        $issue.Summary='The connection was cancelled. The engine finished without retaining an active session-state file.'
        $issue.Solution='Confirm normal internet access before changing settings. The complete rollback record remains in Activity.'
        $issue.Severity='Warning'
    }

    if($done -in @('ProvisionHelpers','ImportComponents','UpdatePrepare','UpdateInstall','UpdateRollback') -and -not $issue){
        $t=$null;$fresh=$false
        try {
            $t=Read-Json $script:TransferProgressPath
            $fresh=($t -and [string]$t.action -eq $done -and [string]$t.state -eq 'Completed' -and
                ([datetime]::Parse([string]$t.updatedUtc)).ToUniversalTime() -ge $script:TransferStartedUtc.AddSeconds(-3))
        }catch{}
        if(-not $fresh){
            $issue=Get-VeylIssue -Action $done -Text 'The worker exited without a fresh, verified completion record.' -ExitCode 1
            $issue.Title='Component download or installation not confirmed'
            $issue.Summary='VeylRoute cannot confirm that the component operation finished or installed its files.'
            $issue.Solution='Refresh component status and check which files are still missing. Do not assume the transfer succeeded. If the problem repeats, use optional technical details to share the worker log.'
            $issue.ActionLabel='Open component setup';$issue.ActionKey='Updates'
        }
    }
    if($issue -and $done -in @('Start','Status','Health')){$script:VerifiedThisSession=$false}
    if ($issue) {Set-Footer ("${done}: "+[string]$issue.Title+'. Open the guidance for next steps.')}
    else {Set-Footer ("$done completed. "+$recovery)}
    if ($code -eq 0 -and -not $issue -and $done -in @('Start','Status','Health')) { Populate-StatusCards $completedLog }
    if(-not $issue -and $done -eq 'Start') { Set-VeylPrivacyPending }
    if($done -in @('Status','Health') -and (Has-Session) -and $completedLog -match '(?im)^\s*Overall\s*:') { Show-VeylPrivacyStatus $completedLog }
    if($issue -and $done -in @('Start','Status','Health')) {
        if($done -in @('Status','Health') -and (Has-Session) -and $completedLog -notmatch '(?im)^\s*Overall\s*:'){
            foreach($name in @('PrivacyTor','PrivacyDns','PrivacyIpv6','PrivacyFirewall')){
                Set-VeylPrivacyRow $name 'NOT VERIFIED' 'The current health check did not finish' 'Danger'
            }
            Set-VeylPrivacyRow 'PrivacyLeak' 'UNVERIFIED' 'Independent DNS-path evidence is unavailable' 'Warning'
            $script:Ui.PrivacyRemedy.Text='Do not trust stale protection checks. Review Activity and disconnect safely if verification remains unavailable.'
        }
        $script:Ui.PrivacyHeadline.Text='Latest check needs attention'
        $script:Ui.PrivacyCheckedAt.Text='See the short error dialog and Activity for details'
    }

    if ($code -eq 0 -and -not $issue -and (Has-Session) -and $done -in @('Start','Status','Health') -and $script:VerifiedThisSession) {
        try { Save-StatusCache (Read-Text $script:LastLog) } catch {}
        $script:Ui.AutoRefreshNotice.Text='Status checked '+(Get-Date -Format 'HH:mm:ss')+' | Next automatic check in 3 minutes.'
    } elseif ($issue -and $done -in @('Start','Status','Health')) {
        $script:Ui.AutoRefreshNotice.Text='The latest check needs attention. Open the on-screen guidance.'
    }
    if($done -eq 'ExitAvailability'){
        Load-VeylExitAvailability
        Refresh-CountryList
        Refresh-FixedChoices
    }
    if ($done -eq 'Updates' -or $done -in @('UpdatePrepare','UpdateInstall','UpdateRollback')) {
        Refresh-VersionCards
        Refresh-UpdateStage
    }
    if($done -eq 'NewCircuit' -and -not $issue -and $code -eq 0) {
        # Existing streams keep their circuits; request a full independent health refresh.
        $script:AutoStatusLastStart=[datetime]::MinValue
        $script:AutoStatusInitialDue=(Get-Date).AddSeconds(2)
        $script:Ui.AutoRefreshNotice.Text='New circuit request sent. Refreshing Tor status for new connections...'
    }
    if ($done -eq 'Start' -and -not $issue -and $code -eq 0) {
        $script:AutoStatusLastStart=[datetime]::MinValue
        $script:AutoStatusInitialDue=(Get-Date).AddSeconds(3)
    }

    Update-SessionUI
    if($done -eq 'Start' -and $script:CancelFile){
        try{Remove-Item -LiteralPath $script:CancelFile -Force -ErrorAction SilentlyContinue}catch{}
        $script:CancelFile=''
        $script:CancelRequested=$false
    }
    if($done -in @('ProvisionHelpers','ImportComponents','UpdatePrepare','UpdateInstall','UpdateRollback')){Refresh-VeylTransferUI}
    if($done -in @('Inventory','ProvisionHelpers','ImportComponents','UpdatePrepare','UpdateInstall','UpdateRollback','Preflight')){
        [void](Refresh-VeylComponentReadiness)
    }
    $script:Ui.DashboardLastAction.Text=if($issue){$done+': '+[string]$issue.Title}else{$done+' completed at '+(Get-Date -Format HH:mm:ss)}
    if($issue){Present-VeylIssue $issue -Automatic $wasAutomatic}
    else{
        $script:LastAutomaticIssueSignature=''
        if(-not $wasAutomatic){Show-VeylOperationSummary $done $completedLog}
    }
    if (-not $script:Window.IsVisible -and $script:TrayIcon -and -not $issue) {
        try {
            $script:TrayIcon.BalloonTipTitle='VeylRoute '+$done
            $script:TrayIcon.BalloonTipText=if ($code -eq 0) {'Operation completed.'} else {'Operation failed. Restore VeylRoute to review the on-screen guidance.'}
            $script:TrayIcon.BalloonTipIcon=if ($code -eq 0) {[System.Windows.Forms.ToolTipIcon]::Info} else {[System.Windows.Forms.ToolTipIcon]::Warning}
            $script:TrayIcon.ShowBalloonTip(1800)
        } catch {}
    }
}
function Hide-ToTray {
    if (-not $script:Window) { return }
    $script:Window.Hide()
    $script:Window.ShowInTaskbar=$false
    if (-not $script:TrayHintShown -and $script:TrayIcon) {
        $script:TrayHintShown=$true
        try {
            $script:TrayIcon.BalloonTipTitle='VeylRoute running in tray'
            $script:TrayIcon.BalloonTipText='The controller was hidden; the tunnel connection is unchanged.'
            $script:TrayIcon.ShowBalloonTip(2000)
        } catch {}
    }
}
function Restore-Window {
    if (-not $script:Window) { return }
    if(-not $script:Window.Dispatcher.CheckAccess()){
        [void]$script:Window.Dispatcher.BeginInvoke([action]{Restore-Window})
        return
    }
    $wasTopmost=$script:Window.Topmost
    try {
        # Show BEFORE changing minimized state. A hidden minimized WPF window may otherwise
        # reappear only on the taskbar instead of in the foreground.
        $script:Window.ShowInTaskbar=$true
        if(-not $script:Window.IsVisible){$script:Window.Show()}
        $script:Window.WindowState=[System.Windows.WindowState]::Normal
        $script:Window.ShowActivated=$true
        $script:Window.Topmost=$true
        [void]$script:Window.Activate()
        [void]$script:Window.Focus()
        try {
            $hwnd=([System.Windows.Interop.WindowInteropHelper]::new($script:Window)).Handle
            if($hwnd -ne [IntPtr]::Zero){
                [void][VeylRouteNativeIdentity]::ShowWindowAsync($hwnd,9)
                [void][VeylRouteNativeIdentity]::SetForegroundWindow($hwnd)
            }
        }catch{}
    }finally{$script:Window.Topmost=$wasTopmost}
    if($script:PendingIssue){
        $pending=$script:PendingIssue
        $script:PendingIssue=$null
        Present-VeylIssue $pending
    }
}
function Exit-Gui {
    $script:ExitRequested=$true
    Restore-Window
    $script:Window.Close()
}

function Paste-BridgesFromClipboard {
    try {
        if (-not [System.Windows.Clipboard]::ContainsText()) {
            Notice 'The clipboard contains no text. Copy the complete obfs4 bridge lines and try again.' 'Paste obfs4 bridges'
            return
        }
        $text=[System.Windows.Clipboard]::GetText([System.Windows.TextDataFormat]::UnicodeText)
        if ([string]::IsNullOrWhiteSpace($text)) {
            Notice 'The clipboard contains no bridge text.' 'Paste obfs4 bridges'
            return
        }
        if ($text.Length -gt 100000) { throw 'Clipboard text exceeds the 100 KB bridge-editor limit.' }
        $text=Convert-ToCRLF $text
        $box=$script:Ui.TxtBridges
        if ([string]::IsNullOrWhiteSpace($box.Text)) {
            $box.Text=$text.TrimEnd()+"`r`n"
            $box.CaretIndex=$box.Text.Length
        } else {
            $box.SelectedText=$text
            $box.CaretIndex=$box.SelectionStart + $box.SelectionLength
        }
        [void]$box.Focus()
        $script:Ui.BridgeCount.Text='Bridge text pasted. Validate format, then Save configuration.'
        Set-Footer 'Bridge text pasted locally; nothing was saved or sent.'
    } catch {
        Notice ('Unable to paste the clipboard: '+$_.Exception.Message) 'Paste obfs4 bridges' ([System.Windows.MessageBoxImage]::Warning)
    }
}

# Wheel handoff: scroll text contents when there is more to read; otherwise move the containing page.
# Prevents single-line fields and the ends of multiline editors from trapping vertical page scrolling.
function Route-TTNestedWheel([object]$source,[System.Windows.Input.MouseWheelEventArgs]$eventArgs) {
    if ($eventArgs.Handled) { return }
    if ($source -is [System.Windows.Controls.ComboBox] -and $source.IsDropDownOpen) { return }
    if ($source -is [System.Windows.Controls.TextBox]) {
        try {
            [void]$source.ApplyTemplate()
            $inner=$source.Template.FindName('PART_ContentHost',$source)
            if ($inner -is [System.Windows.Controls.ScrollViewer]) {
                $canUp=($inner.VerticalOffset -gt 0.5)
                $canDown=($inner.VerticalOffset -lt ($inner.ScrollableHeight - 0.5))
                if (($eventArgs.Delta -gt 0 -and $canUp) -or ($eventArgs.Delta -lt 0 -and $canDown)) { return }
            }
        } catch { }
    }
    $parent=$source
    while ($null -ne $parent) {
        try { $parent=[System.Windows.Media.VisualTreeHelper]::GetParent($parent) }
        catch { break }
        if ($parent -is [System.Windows.Controls.ScrollViewer]) {
            if ($parent.ScrollableHeight -le 0.5) { return }
            $eventArgs.Handled=$true
            $notches=[math]::Max(1, [math]::Abs($eventArgs.Delta)/120.0)
            $distance=72.0*$notches
            if ($eventArgs.Delta -gt 0) { $distance = -$distance }
            $newPosition=[math]::Max(0.0,[math]::Min($parent.ScrollableHeight,$parent.VerticalOffset+$distance))
            $parent.ScrollToVerticalOffset($newPosition)
            return
        }
    }
}
function Wire-TTScrolling {
    foreach ($name in @('TxtCountrySearch','TxtDoh1','TxtDoh2','TxtDohEndpoint','TxtBridges','TxtSocksPort','TxtRouteMetric','TxtBootstrap','TxtAttempts','TxtProbeDelay','CmbRouteMode','CmbCountryMode','CmbFixedCountry','CmbDohProvider')) {
        $control=$script:Ui[$name]
        if ($null -ne $control) {
            $control.Add_PreviewMouseWheel({ param($sender,[System.Windows.Input.MouseWheelEventArgs]$wheelEventArgs) Route-TTNestedWheel $sender $wheelEventArgs })
        }
    }
}


function Copy-VeylLog {
    $text=[string]$script:Ui.TxtLog.Text
    if([string]::IsNullOrWhiteSpace($text)){
        Notice 'There is no diagnostic text to copy yet. Run a check first.' 'Copy log'
        return
    }
    $reason=''
    for($attempt=0;$attempt -lt 5;$attempt++){
        try{
            [System.Windows.Forms.Clipboard]::SetDataObject($text,$true,3,120)
            Set-Footer 'Diagnostic output copied to the clipboard.'
            return
        }catch{
            $reason=$_.Exception.Message
            Start-Sleep -Milliseconds 120
        }
    }
    $issue=Get-VeylIssue -Action 'Copy log' -Text ('Windows clipboard is busy: '+$reason)
    Present-VeylIssue $issue
}

function Wire-Events {
    foreach ($page in @('Dashboard','Countries','Dns','Apps','Bridges','Security','Updates','Activity','Maintenance')) {
        $pageName=$page
        $script:Ui['Nav'+$page].Tag=$page
        $script:Ui['Nav'+$page].Add_Click({ param($sender,$eventArgs) Show-Page ([string]$sender.Tag) })
    }
    $script:Ui.BtnOpenActivity.Add_Click({ Show-Page 'Activity' })
    $script:Ui.BtnCheckExits.Add_Click({
        try{Run-Action 'ExitAvailability'}
        catch{Notice $_.Exception.Message 'Exit availability unavailable' ([System.Windows.MessageBoxImage]::Error)}
    })
    $script:Ui.BtnPrivacyRecheck.Add_Click({
        try{if(Has-Session){Run-Action 'Health'}else{Notice 'Connect to Tor first to run privacy checks.' 'Privacy checks'}}
        catch{Notice $_.Exception.Message 'Health check unavailable' ([System.Windows.MessageBoxImage]::Error)}
    })
    $script:Ui.BtnSetupGuide.Add_Click({try{Show-VeylSetupGuide}catch{Notice $_.Exception.Message 'Setup guide' ([System.Windows.MessageBoxImage]::Error)}})
    $script:Ui.BtnExitGui.Add_Click({Exit-Gui})
    $script:Ui.BtnTheme.Add_Click({
        if ([System.Windows.SystemParameters]::HighContrast) { Notice 'Windows high contrast is active; the OS theme is retained.'; return }
        $target=if ($script:CurrentTheme -eq 'dark') {'light'} else {'dark'}
        Apply-Theme $target
    })
    $script:Ui.TxtCountrySearch.Add_TextChanged({ if ($script:UiReady) { Refresh-CountryList } })
    $script:Ui.CmbCountryMode.Add_SelectionChanged({
        if ($script:UiReady) { $script:Ui.CmbFixedCountry.IsEnabled=($script:Ui.CmbCountryMode.SelectedIndex -eq 0) }
    })
    $script:Ui.BtnSelectVisible.Add_Click({
        foreach ($check in $script:Ui.ListCountries.Items) { $script:Selected[[string]$check.Tag]=$true }
        Refresh-CountryList;Refresh-FixedChoices
    })
    $script:Ui.BtnClearCountries.Add_Click({
        if (Ask 'Clear the exit-country allow-list? You will need to select at least one country before saving.' 'Exit countries') {
            $script:Selected.Clear();Refresh-CountryList;Refresh-FixedChoices
        }
    })
    $script:Ui.CmbDohProvider.Add_SelectionChanged({
        if ($script:SuppressDoh) { return }
        $name=[string]$script:Ui.CmbDohProvider.SelectedItem
        foreach ($preset in $script:DohPresets) {
            if ($name -eq $preset.Name) {
                $script:SuppressDoh=$true
                try {
                    $script:Ui.TxtDoh1.Text=$preset.Primary;$script:Ui.TxtDoh2.Text=$preset.Secondary;$script:Ui.TxtDohEndpoint.Text=$preset.Endpoint
                } finally { $script:SuppressDoh=$false }
                return
            }
        }
    })
    foreach ($box in @('TxtDoh1','TxtDoh2','TxtDohEndpoint')) {
        $script:Ui[$box].Add_TextChanged({ if ($script:UiReady) { Update-DohPresetFromText } })
    }
    $script:Ui.BtnGetBridges.Add_Click({ Open-OfficialBridgePage })
    $script:Ui.BtnPasteBridges.Add_Click({ Paste-BridgesFromClipboard })
    $script:Ui.TxtBridges.Add_PreviewKeyDown({
        param($sender,[System.Windows.Input.KeyEventArgs]$keyEventArgs)
        if (($keyEventArgs.Key -eq [System.Windows.Input.Key]::V -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) -or
            ($keyEventArgs.Key -eq [System.Windows.Input.Key]::Insert -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Shift))) {
            $keyEventArgs.Handled=$true
            Paste-BridgesFromClipboard
        }
    })
    $script:Ui.BtnValidateBridges.Add_Click({
        try {
            $n=Validate-Bridges $script:Ui.TxtBridges.Text
            $script:Ui.BridgeCount.Text="$n obfs4 bridge entries passed structural validation."
            Notice "$n bridge lines passed format validation. Reachability is verified when Tor starts." 'Bridge validation'
        } catch { Notice $_.Exception.Message 'Bridge validation' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.BtnAddApp.Add_Click({
        try {
            $dialog=New-Object Microsoft.Win32.OpenFileDialog
            $dialog.Filter='Executables (*.exe)|*.exe'
            $dialog.Title='Choose an app to use the direct ISP connection'
            $dialog.CheckFileExists=$true
            if ($dialog.ShowDialog($script:Window) -ne $true) { return }
            $path=[IO.Path]::GetFullPath($dialog.FileName)
            foreach($item in $script:Ui.ListApps.Items) {
                if ([string]::Equals([string]$item,$path,[StringComparison]::OrdinalIgnoreCase)) { Notice 'This executable is already included.'; return }
            }
            [void]$script:Ui.ListApps.Items.Add($path)
        } catch { Notice $_.Exception.Message 'Add executable' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.BtnRemoveApp.Add_Click({
        $selected=$script:Ui.ListApps.SelectedItem
        if ($null -ne $selected) { [void]$script:Ui.ListApps.Items.Remove($selected) }
    })
    $script:Ui.BtnSave.Add_Click({
        try { [void](Save-Config $false); Notice 'Settings saved. Changes apply at the next connection.' }
        catch { Notice $_.Exception.Message 'Configuration not saved' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.BtnReload.Add_Click({
        try { if (Ask 'Discard unsaved edits and reload settings from disk?' 'Reload settings') { Load-Config } }
        catch { Notice $_.Exception.Message 'Reload failed' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.CmbRouteMode.Add_SelectionChanged({ if($script:UiReady){Update-RouteWarning} })
    $script:Ui.BtnAddTorApp.Add_Click({
        try{
            $dialog=New-Object Microsoft.Win32.OpenFileDialog
            $dialog.Filter='Executables (*.exe)|*.exe';$dialog.Title='Choose an executable to use Tor in SelectedAppsOnly mode'
            $dialog.CheckFileExists=$true
            if($dialog.ShowDialog($script:Window) -ne $true){return}
            $path=[IO.Path]::GetFullPath($dialog.FileName)
            foreach($item in $script:Ui.ListTorApps.Items){if([string]::Equals([string]$item,$path,[StringComparison]::OrdinalIgnoreCase)){return}}
            [void]$script:Ui.ListTorApps.Items.Add($path)
        }catch{Notice $_.Exception.Message 'TOR app selection' ([System.Windows.MessageBoxImage]::Error)}
    })
    $script:Ui.BtnRemoveTorApp.Add_Click({
        $item=$script:Ui.ListTorApps.SelectedItem
        if($null -ne $item){[void]$script:Ui.ListTorApps.Items.Remove($item)}
    })
    $script:Ui.BtnNewCircuit.Add_Click({
        try {
            if(Ask 'Request fresh circuits for NEW Tor connections? Existing downloads and open streams keep their circuits; a different exit IP is not guaranteed.' 'Request new Tor circuit'){
                Run-Action 'NewCircuit'
            }
        }catch{Notice $_.Exception.Message 'New circuit unavailable' ([System.Windows.MessageBoxImage]::Error)}
    })
    $script:Ui.BtnStart.Add_Click({
        try { [void](Save-Config $true);Run-Action 'Start' }
        catch { Notice $_.Exception.Message 'Unable to connect' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.BtnStop.Add_Click({
        try {
            if((In-Progress) -and $script:BusyAction -eq 'Start'){
                if(Ask 'Request cancellation? Tor may take a few seconds to stop safely while the engine restores any changed Windows settings. Do not force-close the process.' 'Cancel connection'){
                    Request-VeylStartCancellation
                }
            }elseif(Ask 'Disconnect VeylRoute using its original Stop script and restore saved Windows network settings?' 'Disconnect'){
                Run-Action 'Stop'
            }
        }
        catch { Notice $_.Exception.Message 'Unable to disconnect' ([System.Windows.MessageBoxImage]::Error) }
    })
    foreach ($button in @('BtnRecover','BtnRecoveryMaintenance')) {
        $script:Ui[$button].Add_Click({
            try { if (Ask 'Run the existing recovery/rollback script? This restores Windows network settings only as recorded in session state.' 'Controlled recovery') { Run-Action 'Recover' } }
            catch { Notice $_.Exception.Message 'Recovery unavailable' ([System.Windows.MessageBoxImage]::Error) }
        })
    }
    foreach ($pair in @(@('BtnStatus','Status'),@('BtnHealth','Health'),@('BtnPreflight','Preflight'),@('BtnUpdates','Updates'))) {
        $script:Ui[$pair[0]].Tag=$pair[1]
        $script:Ui[$pair[0]].Add_Click({
            param($sender,$eventArgs)
            try { Run-Action ([string]$sender.Tag) }
            catch { Notice $_.Exception.Message 'Operation unavailable' ([System.Windows.MessageBoxImage]::Error) }
        })
    }
    $script:Ui.BtnInventory.Add_Click({try{Run-Action 'Inventory'}catch{Notice $_.Exception.Message 'Component inventory' ([System.Windows.MessageBoxImage]::Error)}})
    $script:Ui.BtnProvisionHelpers.Add_Click({
        try{
            if(Ask 'Download official Wintun and tun2socks Windows AMD64 packages, verify pinned SHA256 checksums and Wintun signature, then install with backups?' 'Install Wintun + tun2socks'){
                Run-Action 'ProvisionHelpers'
            }
        }catch{Notice $_.Exception.Message 'Helper setup failed' ([System.Windows.MessageBoxImage]::Error)}
    })
    $script:Ui.BtnImportComponents.Add_Click({
        try{
            $folder=New-Object System.Windows.Forms.FolderBrowserDialog
            $folder.Description='Select a trusted existing TorTunnel folder, Tor bundle folder or helper-binary folder'
            if($folder.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){return}
            $script:PendingImportDirectory=[string]$folder.SelectedPath
            if(Ask 'Import binaries from the folder you selected? Imported binaries are trusted by you; they are NOT automatically signature-verified. Existing components are backed up.' 'Import existing binaries'){
                Run-Action 'ImportComponents'
            }
        }catch{Notice $_.Exception.Message 'Binary import failed' ([System.Windows.MessageBoxImage]::Error)}
    })
    $script:Ui.BtnTorReleases.Add_Click({ [void][Diagnostics.Process]::Start('https://download.torproject.org/tor/') })
    $script:Ui.BtnPrepareUpdate.Add_Click({
        try {
            $script:PendingSignedImportDirectory=''
            if (Ask 'Download the official stable Windows x64 Expert Bundle from dist.torproject.org and verify its detached OpenPGP signature? No installed binaries will be modified.' 'Prepare signed Tor update') {
                Run-Action 'UpdatePrepare'
            }
        } catch { Notice $_.Exception.Message 'Update preparation unavailable' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.BtnImportSignedUpdate.Add_Click({
        try {
            $chooser=New-Object System.Windows.Forms.FolderBrowserDialog
            $chooser.Description='Select a folder containing signed Windows Expert Bundle (.tar.gz), matching .asc and optional tor-signing-key.asc'
            if($chooser.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){return}
            $script:PendingSignedImportDirectory=[string]$chooser.SelectedPath
            if (Ask 'Verify the local Windows x64 Expert Bundle and matching .asc signature using the pinned Tor Developers key? No binaries will be installed until you approve installation.' 'Import signed Tor bundle') {
                Run-Action 'UpdatePrepare'
            }
        } catch { Notice $_.Exception.Message 'Signed import unavailable' ([System.Windows.MessageBoxImage]::Error) }
        finally { $script:PendingSignedImportDirectory='' }
    })
    $script:Ui.BtnInstallUpdate.Add_Click({
        try {
            if (Ask 'Install the signature-verified Tor Expert Bundle now? The connection must be STOPPED, original Tor files will be retained for rollback, and a later connection test is still required.' 'Install signed Tor update') {
                Run-Action 'UpdateInstall'
            }
        } catch { Notice $_.Exception.Message 'Installation unavailable' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.BtnRollbackUpdate.Add_Click({
        try {
            if (Ask 'Restore the previous Tor folder from the last signed-bundle update? The connection must be STOPPED. The currently installed binaries will be kept separately.' 'Rollback Tor binaries') {
                Run-Action 'UpdateRollback'
            }
        } catch { Notice $_.Exception.Message 'Rollback unavailable' ([System.Windows.MessageBoxImage]::Error) }
    })
    $script:Ui.BtnCopyLog.Add_Click({ Copy-VeylLog })
    $script:Ui.BtnOpenLogFolder.Add_Click({
        try{
            if(Test-Path -LiteralPath $script:LogDir){[void][Diagnostics.Process]::Start('explorer.exe','"'+$script:LogDir+'"')}
            else{Notice 'No log folder exists yet. Run a check to generate diagnostics.' 'Open diagnostic folder'}
        }catch{Notice $_.Exception.Message 'Unable to open diagnostic folder' ([System.Windows.MessageBoxImage]::Error)}
    })
    foreach($pair in @(@('BtnTidy','Tidy'),@('BtnUntidy','Untidy'))) {
        $script:Ui[$pair[0]].Tag=$pair[1]
        $script:Ui[$pair[0]].Add_Click({
            param($sender,$eventArgs)
            try {
                $action=[string]$sender.Tag
                if (Ask 'Change Explorer visibility for root support scripts? Files will not be moved or deleted.' 'Folder maintenance') { Run-Action $action }
            } catch { Notice $_.Exception.Message 'Maintenance unavailable' ([System.Windows.MessageBoxImage]::Error) }
        })
    }
}
function Wire-Tray {
    $script:TrayIcon=New-Object System.Windows.Forms.NotifyIcon
    foreach ($kind in @('disconnected','connected','connecting','warning')) {
        $icoFile=Join-Path $PSScriptRoot ('assets\VeylRoute-'+$kind+'.ico')
        if (Test-Path -LiteralPath $icoFile -PathType Leaf) {
            try { $script:TrayArt[$kind]=New-Object System.Drawing.Icon($icoFile) } catch {}
        }
    }
    $script:TrayIcon.Icon=[System.Drawing.SystemIcons]::Application
    if ($script:TrayArt.ContainsKey('disconnected')) { $script:TrayIcon.Icon=$script:TrayArt['disconnected'];$script:TrayCurrent='disconnected' }
    try {
        $iconFile=Join-Path $PSScriptRoot 'assets\VeylRoute-disconnected.ico'
        if (Test-Path -LiteralPath $iconFile) { $script:Window.Icon=[System.Windows.Media.Imaging.BitmapFrame]::Create([uri]$iconFile) }
    } catch {}
    $script:TrayIcon.Text='VeylRoute Control Center'
    $script:TrayMenu=New-Object System.Windows.Forms.ContextMenuStrip
    $open=New-Object System.Windows.Forms.ToolStripMenuItem 'Open dashboard'
    $status=New-Object System.Windows.Forms.ToolStripMenuItem 'Run status check'
    $quit=New-Object System.Windows.Forms.ToolStripMenuItem 'Exit GUI (leave Tor connection unchanged)'
    [void]$script:TrayMenu.Items.Add($open)
    [void]$script:TrayMenu.Items.Add($status)
    [void]$script:TrayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$script:TrayMenu.Items.Add($quit)
    $script:TrayIcon.ContextMenuStrip=$script:TrayMenu
    $script:TrayIcon.Visible=$true
    $open.Add_Click({ Restore-Window })
    $status.Add_Click({ try { if (-not (In-Progress)) { Run-Action 'Status' } else { Restore-Window } } catch { Restore-Window; Notice $_.Exception.Message 'Status failed' ([System.Windows.MessageBoxImage]::Error) } })
    $quit.Add_Click({ Exit-Gui })
    $script:TrayIcon.Add_DoubleClick({ Restore-Window })
    $script:Window.Add_StateChanged({
        if ($script:Window.WindowState -eq [System.Windows.WindowState]::Minimized -and -not $script:ExitRequested) { Hide-ToTray }
    })
    $script:Window.Add_Closing({
        param($sender,$eventArgs)
        if (-not $script:ExitRequested) {
            $eventArgs.Cancel=$true
            Hide-ToTray
            return
        }
        if (In-Progress) {
            if (-not (Ask "A $($script:BusyAction) worker is running. Close the GUI and let it continue without monitoring?" 'Exit GUI')) {
                $eventArgs.Cancel=$true;$script:ExitRequested=$false;return
            }
        } elseif (Has-Session) {
            if (-not (Ask 'Exit only the GUI while leaving VeylRoute connected? Use Disconnect to restore your normal Internet connection.' 'Exit GUI')) {
                $eventArgs.Cancel=$true;$script:ExitRequested=$false;return
            }
        }
    })
    $script:Window.Add_Closed({
        try { if ($script:Timer) { $script:Timer.Stop() } } catch {}
        try { if ($script:TrayIcon) { $script:TrayIcon.Visible=$false;$script:TrayIcon.Dispose() } } catch {}
        foreach ($ico in $script:TrayArt.Values) { try { $ico.Dispose() } catch {} }
        try { if ($script:TrayMenu) { $script:TrayMenu.Dispose() } } catch {}
        try { if ($script:WakeEvent) { $script:WakeEvent.Dispose() } } catch {}
        try { if ($script:Mutex) { $script:Mutex.ReleaseMutex();$script:Mutex.Dispose() } } catch {}
    })
}

function Initialize-VeylTaskbarIdentity {
    try {
        if(-not ('VeylRouteNativeIdentity' -as [type])){
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class VeylRouteNativeIdentity {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int command);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
'@ -ErrorAction Stop
        }
        $code=[VeylRouteNativeIdentity]::SetCurrentProcessExplicitAppUserModelID('Scopewise.VeylRoute.ControlCenter')
        if($code -ne 0){Set-Footer 'Windows did not accept the custom taskbar identity.'}
    }catch{try{Set-Footer ('Taskbar icon identity unavailable: '+$_.Exception.Message)}catch{}}
}

function GUI-Startup {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) { throw 'Missing config\settings.json in this VeylRoute installation.' }
    if (-not (Test-Path -LiteralPath $script:WorkerPath -PathType Leaf)) { throw 'Universal GUI worker is missing under _internal\gui.' }
    if (-not (Test-Path -LiteralPath $script:PowerShellExe -PathType Leaf)) { throw 'Windows PowerShell 5.1 is required.' }
    $mutexNew=$false
    $script:Mutex=[System.Threading.Mutex]::new($true,'Local\TorTunnelGUIControlCenterR1',[ref]$mutexNew)
    if (-not $mutexNew) {
        try {
            $wake=[System.Threading.EventWaitHandle]::OpenExisting('Local\TorTunnelGUIRestoreR13')
            try { [void]$wake.Set() } finally { $wake.Dispose() }
        } catch { Notice 'VeylRoute is already open. Use the notification-area icon to restore it.' }
        $script:Mutex.Dispose();$script:Mutex=$null
        return
    }
    try {
        $script:WakeEvent=New-Object System.Threading.EventWaitHandle -ArgumentList @($false,[System.Threading.EventResetMode]::AutoReset,'Local\TorTunnelGUIRestoreR13')
    } catch { $script:WakeEvent=$null }
    Initialize-VeylTaskbarIdentity
    $xamlPath=Join-Path $PSScriptRoot 'TorTunnel.ModernGui.xaml'
    if (-not (Test-Path -LiteralPath $xamlPath -PathType Leaf)) { throw 'Missing WPF layout: TorTunnel.ModernGui.xaml' }
    [xml]$xml=Read-Text $xamlPath
    $reader=New-Object System.Xml.XmlNodeReader($xml)
    $script:Window=[System.Windows.Markup.XamlReader]::Load($reader)
    $script:App=New-Object System.Windows.Application
    $script:App.ShutdownMode=[System.Windows.ShutdownMode]::OnMainWindowClose
    $script:App.Add_SessionEnding({ $script:ExitRequested=$true })
    $names=@(
        'BtnTheme','LblTheme','BtnSetupGuide','BtnExitGui','CmbRouteMode','LblRouteWarning','AutoRefreshNotice','UpdateStage','BtnPrepareUpdate','BtnImportSignedUpdate','BtnInstallUpdate','BtnRollbackUpdate','HeaderTitle','HeaderSubtitle','HeaderState','StatusDot','HeroState','HeroDescription','FooterText',
        'DashboardLastAction','PrivacyHeadline','PrivacyCheckedAt','BtnPrivacyRecheck','PrivacyTorValue','PrivacyTorNote','PrivacyDnsValue','PrivacyDnsNote',
        'PrivacyLeakValue','PrivacyLeakNote','PrivacyIpv6Value','PrivacyIpv6Note','PrivacyFirewallValue','PrivacyFirewallNote','PrivacyRemedy',
        'CardIp','CardIpNote','CardCountry','CardCountryNote','CardDns','CardDnsNote','CardRoute','CardRouteNote',
        'BtnStart','BtnStop','LblBtnStop','BtnNewCircuit','BtnStatus','BtnHealth','BtnPreflight','BtnRecover','BtnOpenActivity',
        'BtnCheckExits','CountryAvailabilityNote','TxtCountrySearch','ListCountries','CountryCount','BtnSelectVisible','BtnClearCountries','CmbCountryMode','CmbFixedCountry','CbStrictCountry',
        'CmbDohProvider','TxtDoh1','TxtDoh2','TxtDohEndpoint','CbEnableApps','ListApps','BtnAddApp','BtnRemoveApp',
        'CbEnableTorApps','CbTorAppKillSwitch','CbBlockTorAppUdp','ListTorApps','BtnAddTorApp','BtnRemoveTorApp',
        'TxtBridges','BridgeCount','BtnValidateBridges','BtnGetBridges','BtnPasteBridges','CbBlockPlainDns','CbDisableIPv6','CbEdgeKill','CbDisableQuic','CbOpenEdge','CbFreshState',
        'TxtSocksPort','TxtRouteMetric','TxtBootstrap','CbRetry','TxtAttempts','TxtProbeDelay',
        'UpdateSummary','InstalledTor','LatestTor','LatestBundle','UpdateNotes','BtnUpdates','BtnTorReleases','BtnInventory','BtnProvisionHelpers','BtnImportComponents',
        'TransferPanel','TransferStatus','TransferStage','TransferProgress','TransferBytes','TransferLocation','TransferDescription',
        'InventorySummary','MissingComponentsPanel','MissingComponentsList','ChipTor','StateTor','ChipLyrebird','StateLyrebird','ChipGeoIP','StateGeoIP',
        'ChipGeoIP6','StateGeoIP6','ChipTun2socks','StateTun2socks','ChipWintun','StateWintun','ChipBridges','StateBridges','ChipSignedUpdate','StateSignedUpdate',
        'LogHeader','LogSeveritySummary','TxtLog','BtnCopyLog','BtnOpenLogFolder','BtnTidy','BtnUntidy','BtnRecoveryMaintenance','BtnReload','BtnSave'
    )
    foreach ($suffix in @('Dashboard','Countries','Dns','Apps','Bridges','Security','Updates','Activity','Maintenance')) {
        $names += 'Page'+$suffix
        $names += 'Nav'+$suffix
    }
    foreach ($name in $names) {
        $control=$script:Window.FindName($name)
        if ($null -eq $control) { throw "WPF control '$name' is missing." }
        $script:Ui[$name]=$control
    }
    foreach ($p in $script:DohPresets) { [void]$script:Ui.CmbDohProvider.Items.Add($p.Name) }
    [void]$script:Ui.CmbDohProvider.Items.Add('Custom')
    Build-Countries
    Wire-Events
    Wire-TTScrolling
    Wire-Tray
    $script:UiReady=$true
    Apply-Theme (Get-ThemePreference)
    Load-Config
    Load-VeylExitAvailability
    Refresh-CountryList
    Show-Page 'Dashboard'
    $script:Window.Add_ContentRendered({
        if(-not $script:WelcomeChecked){
            $script:WelcomeChecked=$true
            if(-not (Test-Path -LiteralPath $script:SetupGuideFlagPath -PathType Leaf)){
                try { Show-VeylSetupGuide -FirstRun $true }
                catch { Set-Footer ('First-run welcome guide unavailable: '+$_.Exception.Message) }
            }
        }
    })
    Refresh-VersionCards
    [void](Refresh-VeylComponentReadiness)
    Refresh-VeylTransferUI
    Update-SessionUI
    try {
        $logs=@(Get-ChildItem -LiteralPath $script:LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
        if ($logs.Count -gt 0) {
            $script:LastLog=$logs[0].FullName
            $script:BusyAction='Last session'
            Update-Log
            $script:BusyAction=''
        }
    } catch {}
    $script:Timer=New-Object System.Windows.Threading.DispatcherTimer
    $script:Timer.Interval=[TimeSpan]::FromMilliseconds(700)
    $script:Timer.Add_Tick({
        try {
            if ($script:WakeEvent -and $script:WakeEvent.WaitOne(0)) { Restore-Window }
            Update-Log
            Finish-Action
            Refresh-VeylTransferUI
            $script:LastPulse++
            if ($script:LastPulse -ge 7) { $script:LastPulse=0;Update-SessionUI;Auto-StatusPulse }
        } catch {
            $problemText=$_.Exception.Message
            Set-Footer ('GUI status needs attention: '+$problemText)
            if($problemText -ne $script:LastGuiInternalFault){
                $script:LastGuiInternalFault=$problemText
                Present-VeylIssue (Get-VeylIssue -Action 'GUI monitoring' -Text $problemText) -Automatic $true
            }
        }
    })
    $script:Timer.Start()
    [void]$script:App.Run($script:Window)
}
try { GUI-Startup }
catch {
    $message='VeylRoute GUI startup error: '+$_.Exception.Message
    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) { [void](New-Item -ItemType Directory -Path $script:LogDir -Force) }
        Add-Content -LiteralPath (Join-Path $script:LogDir 'wpf-startup-errors.log') -Value ((Get-Date -Format o)+' '+$message) -Encoding UTF8
    } catch {}
    Notice $message 'VeylRoute GUI' ([System.Windows.MessageBoxImage]::Error)
    try { if ($script:TrayIcon) { $script:TrayIcon.Visible=$false;$script:TrayIcon.Dispose() } } catch {}
    try { if ($script:WakeEvent) { $script:WakeEvent.Dispose() } } catch {}
    try { if ($script:Mutex) { $script:Mutex.ReleaseMutex();$script:Mutex.Dispose() } } catch {}
}
