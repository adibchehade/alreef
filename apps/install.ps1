<#
    Softserv Tools - a small winget GUI to install, update and remove my usual apps.

    Run from any PowerShell window:
        irm alreef.es/tools | iex

    The app list lives in apps.json next to this script (edit it on GitHub to add apps).
#>

function Start-MyApps {
    $RepoRaw   = 'https://raw.githubusercontent.com/adibchehade/alreef/main/apps'
    $ScriptUrl = "$RepoRaw/install.ps1"
    $AppsUrl   = "$RepoRaw/apps.json"

    # ---------- Relaunch as admin in Windows PowerShell (needed for installs, restore points, WPF) ----------
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $isDesktop = $PSVersionTable.PSEdition -eq 'Desktop'
    $isSta     = [Threading.Thread]::CurrentThread.ApartmentState -eq 'STA'
    if (-not ($isAdmin -and $isDesktop -and $isSta)) {
        $file = $PSCommandPath
        if (-not $file) {
            $file = Join-Path $env:TEMP 'SoftservTools-install.ps1'
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $ScriptUrl -OutFile $file -UseBasicParsing -ErrorAction Stop
            } catch { Write-Host "Couldn't download Softserv Tools: $($_.Exception.Message)" -ForegroundColor Red; return }
        }
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'RemoteSigned', '-STA', '-File', "`"$file`"")
        return
    }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    # ---------- Make sure winget exists (installs it automatically if missing) ----------
    function Find-Winget {
        $c = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
        try {
            $p = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_8wekyb3d8bbwe\winget.exe" -ErrorAction Stop |
                 Sort-Object { try { [version](($_.Path -split '_')[1]) } catch { [version]'0.0' } } -Descending |
                 Select-Object -First 1
            if ($p) { return $p.Path }
        } catch {}
        $null
    }

    $wingetExe = Find-Winget
    if (-not $wingetExe) {
        Write-Host 'winget not found - registering App Installer...' -ForegroundColor Cyan
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch {}
        $wingetExe = Find-Winget
    }
    if (-not $wingetExe) {
        Write-Host 'Installing winget from Microsoft (one time, about a minute)...' -ForegroundColor Cyan
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ProgressPreference = 'SilentlyContinue'
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers | Out-Null
            Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -Scope AllUsers -AllowClobber
            Import-Module Microsoft.WinGet.Client -Force
            Repair-WinGetPackageManager -AllUsers -Latest -Force
        } catch { Write-Host "winget setup failed: $($_.Exception.Message)" -ForegroundColor Red }
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') +
                    ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
        $wingetExe = Find-Winget
    }
    if (-not $wingetExe) {
        # Windows Server / LTSC: install winget and its dependencies straight from Microsoft's GitHub release
        Write-Host 'Installing winget and its dependencies from Microsoft GitHub (Windows Server / LTSC)...' -ForegroundColor Cyan
        try {
            $ProgressPreference = 'SilentlyContinue'
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $tmp = Join-Path $env:TEMP 'winget-setup'
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            $rel = 'https://github.com/microsoft/winget-cli/releases/latest/download'
            Invoke-WebRequest "$rel/DesktopAppInstaller_Dependencies.zip" -OutFile "$tmp\deps.zip" -UseBasicParsing -ErrorAction Stop
            Invoke-WebRequest "$rel/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle" -OutFile "$tmp\winget.msixbundle" -UseBasicParsing -ErrorAction Stop
            Expand-Archive "$tmp\deps.zip" "$tmp\deps" -Force
            $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } elseif ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
            Get-ChildItem "$tmp\deps" -Recurse -Filter *.appx |
                Where-Object { $_.FullName -match "\\$arch\\" -or $_.Name -match "_$arch" } |
                ForEach-Object {
                    Write-Host "  dependency: $($_.Name)" -ForegroundColor DarkGray
                    try { Add-AppxPackage -Path $_.FullName -ErrorAction Stop } catch { Write-Host "    $($_.Exception.Message)" -ForegroundColor DarkGray }
                }
            Add-AppxPackage -Path "$tmp\winget.msixbundle" -ErrorAction Stop
        } catch { Write-Host "Direct install failed: $($_.Exception.Message)" -ForegroundColor Red }
        $env:Path += ";$env:LOCALAPPDATA\Microsoft\WindowsApps"
        $wingetExe = Find-Winget
    }
    if (-not $wingetExe) {
        [Windows.MessageBox]::Show("winget could not be installed automatically.`n`nDownload App Installer from https://aka.ms/getwinget, open it, then run this again.", 'Softserv Tools') | Out-Null
        Start-Process 'https://aka.ms/getwinget'
        return
    }
    Write-Host "Using winget: $wingetExe" -ForegroundColor DarkGray

    # ---------- App list: local apps.json > GitHub apps.json > built-in fallback ----------
    $DefaultAppsJson = @'
[
  { "name": "LibreWolf", "id": "LibreWolf.LibreWolf",      "category": "Browsers",      "homepage": "https://librewolf.net",                       "default": false },
  { "name": "Telegram",  "id": "Telegram.TelegramDesktop", "category": "Communication", "homepage": "https://desktop.telegram.org",                "default": false },
  { "name": "7-Zip",     "id": "7zip.7zip",                "category": "Utilities",     "homepage": "https://www.7-zip.org",                       "default": false },
  { "name": "CCleaner",  "id": "Piriform.CCleaner",        "category": "Utilities",     "homepage": "https://www.ccleaner.com/ccleaner/download", "default": false }
]
'@
    $apps = $null
    if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'apps.json'))) {
        $apps = Get-Content (Join-Path $PSScriptRoot 'apps.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    if (-not $apps) {
        try {
            $apps = Invoke-RestMethod -Uri "$AppsUrl`?t=$([DateTime]::Now.Ticks)" -TimeoutSec 10 -UseBasicParsing
            if ($apps -is [string]) { $apps = $apps | ConvertFrom-Json }
        } catch { $apps = $null }
    }
    if (-not $apps) { $apps = $DefaultAppsJson | ConvertFrom-Json }
    $apps = @($apps)

    # ---------- Window ----------
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Softserv Tools" Width="1060" Height="940" MinWidth="760" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource Bg}" Foreground="{DynamicResource Text}"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="Background" Value="{DynamicResource Btn}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BtnBorder}"/>
      <Setter Property="Padding" Value="13,6"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{DynamicResource AccentText}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.8"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{DynamicResource Accent}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource Accent}"/>
      <Setter Property="Foreground" Value="{DynamicResource OnAccent}"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="{DynamicResource Danger}"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource Text}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="18" Height="18" CornerRadius="5" BorderThickness="1.5"
                      BorderBrush="{DynamicResource CheckBorder}" Background="Transparent" VerticalAlignment="Center">
                <Path x:Name="Tick" Data="M3,8 L6.5,11.5 L12.5,4.5" Stroke="{DynamicResource OnAccent}" StrokeThickness="2.2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="11,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource AccentText}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="{DynamicResource Accent}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Accent}"/>
                <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/>
      <Setter Property="MinWidth" Value="8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb">
                      <Border CornerRadius="4" Background="{DynamicResource Thumb}"/>
                    </ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="24,20,24,18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" Margin="0,0,0,16">
      <Border Width="44" Height="44" CornerRadius="12" Background="{DynamicResource Accent}" Margin="0,0,14,0" VerticalAlignment="Center">
        <Path Data="M22,11 L22,27 M15,21 L22,28 L29,21 M14,33 L30,33" Stroke="{DynamicResource OnAccent}" StrokeThickness="2.6"
              StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
      </Border>
      <Border DockPanel.Dock="Right" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource BtnBorder}" BorderThickness="1"
              CornerRadius="16" Padding="14,6" VerticalAlignment="Center">
        <TextBlock x:Name="Summary" Text="Checking..." Foreground="{DynamicResource Muted}" FontSize="12"/>
      </Border>
      <Button x:Name="BtnRefreshTop" DockPanel.Dock="Right" Content="Refresh" Margin="0,0,10,0"
              Padding="16,7" VerticalAlignment="Center" ToolTip="Re-check what's installed (F5)"/>
      <StackPanel x:Name="ThemePicker" DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="0,0,14,0"/>
      <StackPanel VerticalAlignment="Center">
        <TextBlock Text="Softserv Tools" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock Text="Tick the apps, then choose an action. Installs come from winget or the vendor's signed installer."
                   Foreground="{DynamicResource Muted}" Margin="0,2,0,0"/>
      </StackPanel>
    </DockPanel>

    <Border Grid.Row="1" Background="{DynamicResource Panel}" BorderBrush="{DynamicResource PanelBorder}" BorderThickness="1" CornerRadius="14" Padding="14,4,8,12">
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="AppPanel" Margin="0,0,6,0"/>
      </ScrollViewer>
    </Border>

    <Border Grid.Row="2" Margin="0,14,0,6" Padding="14,12,6,4" CornerRadius="14" BorderThickness="1"
            Background="{DynamicResource Panel}" BorderBrush="{DynamicResource PanelBorder}">
      <StackPanel>
        <DockPanel Margin="0,0,0,4">
          <TextBlock Text="APPS" Width="96" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource AccentText}" VerticalAlignment="Top" Margin="2,11,0,0"/>
          <WrapPanel>
            <Button x:Name="BtnInstall" Style="{StaticResource Primary}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE896;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Install selected" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnUpdate">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE777;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Update selected" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnUninstall" Style="{StaticResource Danger}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE74D;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Uninstall selected" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnUpdateAll">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE895;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Update everything on this PC" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnRefresh">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE72C;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Refresh status" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
          </WrapPanel>
        </DockPanel>
        <Border Height="1" Margin="0,4,8,4" Background="{DynamicResource PanelBorder}"/>
        <DockPanel Margin="0,6,0,0">
          <TextBlock Text="WINDOWS" Width="96" FontSize="11" FontWeight="SemiBold" Foreground="{DynamicResource AccentText}" VerticalAlignment="Top" Margin="2,11,0,0"/>
          <WrapPanel>
            <Button x:Name="BtnRestore">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE81C;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Create restore point" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnScripts" ToolTip="Set-ExecutionPolicy RemoteSigned -Scope CurrentUser">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE756;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Allow PowerShell scripts" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnRdp" ToolTip="Turns off the newer security warning when opening .rdp files (RedirectionWarningDialogVersion = 1)">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE8AF;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Classic RDP warning" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnLiberNT" ToolTip="Wallpaper, dark mode, blue accent, clean taskbar, desktop icons">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE771;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Apply LiberNT look" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="BtnEdge" Style="{StaticResource Danger}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE711;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="14" Margin="0,1,9,0" VerticalAlignment="Center"/>
                <TextBlock Text="Remove Edge" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
          </WrapPanel>
        </DockPanel>
      </StackPanel>
    </Border>

    <Border x:Name="LogPanel" Grid.Row="3" Height="78" Background="{DynamicResource LogBg}" BorderBrush="{DynamicResource PanelBorder}" BorderThickness="1" CornerRadius="12" Padding="4">
      <TextBox x:Name="LogBox" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
               FontFamily="Cascadia Mono, Consolas" FontSize="12" Background="Transparent" Foreground="{DynamicResource LogText}"
               BorderThickness="0" Padding="8,6"/>
    </Border>

    <DockPanel Grid.Row="4" Margin="2,10,2,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
        <TextBlock x:Name="LinkLog"      Text="Bigger log"   Foreground="{DynamicResource AccentText}" Cursor="Hand" Margin="0,0,16,0" ToolTip="Show more or fewer log lines"/>
        <TextBlock x:Name="LinkExpand"   Text="Show all apps"   Foreground="{DynamicResource AccentText}" Cursor="Hand" Margin="0,0,28,0"/>
        <TextBlock x:Name="LinkCollapse" Text="" Visibility="Collapsed"/>
        <TextBlock x:Name="LinkAll"  Text="Select all"  Foreground="{DynamicResource AccentText}" Cursor="Hand" Margin="0,0,16,0"/>
        <TextBlock x:Name="LinkNone" Text="Select none" Foreground="{DynamicResource AccentText}" Cursor="Hand"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal">
        <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="{DynamicResource OkFg}" Margin="0,0,8,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="StatusText" Text="Ready" Foreground="{DynamicResource Muted}" VerticalAlignment="Center"/>
        <ProgressBar x:Name="BusyBar" Width="140" Height="4" Margin="14,0,0,0" IsIndeterminate="True" Visibility="Collapsed"
                     VerticalAlignment="Center" BorderThickness="0" Foreground="{DynamicResource Accent}" Background="{DynamicResource PanelBorder}"/>
      </StackPanel>
    </DockPanel>
  </Grid>
</Window>
'@
    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    foreach ($n in 'AppPanel','BtnInstall','BtnUpdate','BtnUninstall','BtnUpdateAll','BtnRefresh','BtnRestore','BtnEdge','LogBox','LinkAll','LinkNone','StatusText','StatusDot','Summary','BtnRefreshTop','BtnScripts','BtnLiberNT','LinkExpand','LinkCollapse','ThemePicker','BtnRdp','BusyBar','LogPanel','LinkLog') {
        Set-Variable -Name $n -Value $win.FindName($n)
    }
    $buttons = @($BtnRefreshTop, $BtnInstall, $BtnUpdate, $BtnUninstall, $BtnUpdateAll, $BtnRefresh, $BtnRestore, $BtnEdge, $BtnScripts, $BtnLiberNT, $BtnRdp)

    # Open as large as the screen allows
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Width  = [Math]::Min(1060, $wa.Width  - 40)
    $win.Height = [Math]::Min(1000, $wa.Height - 40)
    $win.WindowState = 'Maximized'   # open full screen; Restore Down returns to the size above

    # ---------- Themes ----------
    function Use-Res($el, $prop, [string]$key) { $el.SetResourceReference($prop, $key) }
    $FG   = [Windows.Controls.TextBlock]::ForegroundProperty
    $BG   = [Windows.Controls.Border]::BackgroundProperty
    $BRD  = [Windows.Controls.Border]::BorderBrushProperty
    $STRK = [Windows.Shapes.Shape]::StrokeProperty
    $FILL = [Windows.Shapes.Shape]::FillProperty

    $keys = 'Bg','Panel','PanelBorder','Card','CardBorder','CardHover','Btn','BtnBorder','Text','Muted','Accent','OnAccent',
            'AccentText','AccentHover','LogBg','LogText','CheckBorder','Thumb','Danger',
            'OkFg','OkBg','WarnFg','WarnBg','OffFg','OffBg','WorkFg','WorkBg'
    function New-Theme([string]$label, [string[]]$v) { $t = [ordered]@{ Label = $label }; for ($i = 0; $i -lt $keys.Count; $i++) { $t[$keys[$i]] = $v[$i] }; $t }
    $themes = [ordered]@{
        graphite = New-Theme 'Graphite' @('#111317','#15181D','#23272F','#1B1E24','#2A2F38','#22262E','#1B1E24','#2E333D','#ECEEF2','#9AA3B2','#0077C3','#FFFFFF',
                                         '#3AA0E0','#6CBBEA','#0B0D10','#B8BFCA','#4A515E','#3A404B','#FF8A93',
                                         '#4ADE80','#153024','#FBBF24','#3A2E12','#9AA3B2','#23272F','#6CBBEA','#13293B')
        navy     = New-Theme 'LiberNT navy' @('#08122B','#0C1A3A','#1A2D55','#11234B','#1A3260','#17306A','#11234B','#1E3566','#E6EEF8','#8FA3C4','#0077C3','#FFFFFF',
                                         '#2A94D6','#60B4E8','#050C1E','#B4C3DA','#3D5A8C','#2A4373','#FF8A93',
                                         '#3DDC97','#14302A','#FFB547','#3A2D14','#8FA3C4','#16264A','#60B4E8','#0B2F66')
        teal     = New-Theme 'Midnight teal' @('#0B1416','#0F1B1D','#1C2E31','#132124','#1F3337','#18292D','#132124','#24393D','#E6F2F1','#94A9AC','#14B8A6','#042F2B',
                                         '#2DD4BF','#5EEAD4','#071012','#B3C7C9','#3B5458','#2A4246','#FF8A93',
                                         '#86EFAC','#1B2E1E','#FCD34D','#3A3014','#94A9AC','#1A2A2D','#5EEAD4','#0F3532')
        light    = New-Theme 'Windows light' @('#F3F4F6','#FAFAFB','#E1E4E8','#FFFFFF','#E1E4E8','#EEF5FC','#FFFFFF','#D5D9DF','#1B1F24','#5B6370','#0067C0','#FFFFFF',
                                         '#0067C0','#0A84E0','#FFFFFF','#39404A','#9AA1AB','#C5CAD1','#C42B1C',
                                         '#11703A','#DCF5E5','#8A5300','#FCEFD3','#5B6370','#ECEEF1','#0067C0','#E1EEFB')
    }
    $themeReg = 'HKCU:\Software\SoftservTools'

    function Get-AutoTheme {
        $light = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).AppsUseLightTheme
        if ($light -eq 1) { 'light' } else { 'graphite' }
    }
    function New-Brush([string]$hex) {
        $b = [Windows.Media.SolidColorBrush]::new([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex))
        $b.Freeze()
        ,$b
    }

    function Set-Theme([string]$name) {
        if ($name -ne 'auto' -and -not $themes.Contains($name)) { $name = 'auto' }
        $script:themeChoice = $name
        $t = $themes[$(if ($name -eq 'auto') { Get-AutoTheme } else { $name })]
        foreach ($k in $keys) {
            [Windows.Media.SolidColorBrush]$brush = New-Brush $t[$k]   # typed, so WPF gets a real Brush, not a PowerShell wrapper
            $win.Resources.Remove($k)
            $win.Resources.Add($k, $brush.psobject.BaseObject)
        }
        foreach ($sw in $ThemePicker.Children) {
            $sw.BorderThickness = if ($sw.Tag -eq $name) { '2' } else { '1' }
            Use-Res $sw $BRD $(if ($sw.Tag -eq $name) { 'AccentText' } else { 'BtnBorder' })
        }
        try {
            New-Item -Path $themeReg -Force -ErrorAction Stop | Out-Null
            Set-ItemProperty -Path $themeReg -Name Theme -Value $name -ErrorAction Stop
        } catch {}
    }

    # Swatches: Auto + one per theme
    foreach ($name in @('auto') + @($themes.Keys)) {
        $sw = New-Object Windows.Controls.Border
        $sw.Width = 26; $sw.Height = 26; $sw.CornerRadius = '13'; $sw.Margin = '0,0,6,0'; $sw.Cursor = 'Hand'; $sw.Tag = $name
        if ($name -eq 'auto') {
            $sw.Background = New-Brush '#80808080'
            $sw.ToolTip = 'Auto: follows your Windows light/dark setting'
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = 'A'; $tb.FontSize = 11; $tb.FontWeight = 'SemiBold'; $tb.HorizontalAlignment = 'Center'; $tb.VerticalAlignment = 'Center'
            Use-Res $tb $FG 'Text'
            $sw.Child = $tb
        } else {
            $sw.Background = New-Brush $themes[$name].Bg
            $sw.ToolTip = $themes[$name].Label
            $dot = New-Object Windows.Shapes.Ellipse
            $dot.Width = 10; $dot.Height = 10; $dot.Fill = New-Brush $themes[$name].Accent
            $sw.Child = $dot
        }
        $sw.Add_MouseLeftButtonUp({ Set-Theme $this.Tag })
        [void]$ThemePicker.Children.Add($sw)
    }
    $saved = (Get-ItemProperty $themeReg -ErrorAction SilentlyContinue).Theme
    foreach ($oldKey in 'HKCU:\Software\SoftServeTools', 'HKCU:\Software\MyApps') {
        if (-not $saved) { $saved = (Get-ItemProperty $oldKey -ErrorAction SilentlyContinue).Theme }
    }
    Set-Theme $(if ($saved) { $saved } else { 'auto' })

    # ---------- Home: big category tiles; hovering a tile shows its apps below ----------
    $rows = @{}
    $sections = @()
    $script:activeSec = $null
    $script:allPanel  = $null
    $TBK = [Windows.Controls.Border]::BorderThicknessProperty

    $tiles = New-Object Windows.Controls.WrapPanel
    $tiles.Margin = '0,8,0,0'
    [void]$AppPanel.Children.Add($tiles)

    $detailHead = New-Object Windows.Controls.DockPanel
    $detailHead.Margin = '8,18,0,4'
    $detailTitle = New-Object Windows.Controls.TextBlock
    $detailTitle.FontSize = 18; $detailTitle.FontWeight = 'SemiBold'; Use-Res $detailTitle $FG 'Text'
    $detailHint = New-Object Windows.Controls.TextBlock
    $detailHint.Text = 'Hover a card above to switch'; $detailHint.FontSize = 12; $detailHint.Margin = '14,0,0,0'
    $detailHint.VerticalAlignment = 'Bottom'; Use-Res $detailHint $FG 'Muted'
    [void]$detailHead.Children.Add($detailTitle); [void]$detailHead.Children.Add($detailHint)
    [void]$AppPanel.Children.Add($detailHead)

    $detail = New-Object Windows.Controls.ContentControl
    $detail.Margin = '2,0,0,0'
    [void]$AppPanel.Children.Add($detail)

    $glyphs = @{ 'Browsers' = 0xE774; 'Communication' = 0xE8BD; 'Network' = 0xE701; 'Security' = 0xEA18; 'Remote Desktop' = 0xE8AF; 'Antidetect Browsers' = 0xE716; 'Downloads' = 0xE896; 'Developer' = 0xE943; 'Utilities' = 0xE90F;
                 'Runtimes' = 0xE7B8; 'Visual C++ Runtimes' = 0xEC7A }

    function Set-TileLook($sec) {
        $active = [object]::ReferenceEquals($sec, $script:activeSec)
        $hover  = $sec.Tile.IsMouseOver
        Use-Res $sec.Tile $BG  $(if ($hover) { 'CardHover' } else { 'Card' })
        Use-Res $sec.Tile $BRD $(if ($active) { 'Accent' } elseif ($hover) { 'AccentText' } else { 'CardBorder' })
        $sec.Tile.BorderThickness = if ($active) { '2' } else { '1' }
    }
    function Clear-Detail {
        $detail.Content = $null
        if ($script:allPanel) { $script:allPanel.Children.Clear(); $script:allPanel = $null }
    }
    function Show-Category($sec) {
        Clear-Detail
        $detail.Content = $sec.Grid
        $detailTitle.Text = $sec.Name
        $script:activeSec = $sec
        foreach ($s in $sections) { Set-TileLook $s }
    }
    function Show-AllApps {
        Clear-Detail
        $sp = New-Object Windows.Controls.StackPanel
        foreach ($s in $sections) {
            $h = New-Object Windows.Controls.TextBlock
            $h.Text = $s.Name.ToUpper(); $h.FontSize = 11; $h.FontWeight = 'SemiBold'; $h.Margin = '6,14,0,6'
            Use-Res $h $FG 'AccentText'
            [void]$sp.Children.Add($h); [void]$sp.Children.Add($s.Grid)
        }
        $script:allPanel = $sp
        $detail.Content = $sp
        $detailTitle.Text = 'All apps'
        $script:activeSec = $null
        foreach ($s in $sections) { Set-TileLook $s }
    }

    foreach ($cat in ($apps | ForEach-Object { $_.category } | Select-Object -Unique)) {
        $catApps = @($apps | Where-Object { $_.category -eq $cat })

        $grid = New-Object Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 3

        # The big tile
        $tile = New-Object Windows.Controls.Border
        $tile.Width = 250; $tile.Height = 98; $tile.Margin = '5'; $tile.CornerRadius = '14'; $tile.Padding = '16,10'
        $tile.Cursor = 'Hand'; $tile.BorderThickness = '1'
        $tsp = New-Object Windows.Controls.StackPanel

        $top = New-Object Windows.Controls.DockPanel
        $badge = New-Object Windows.Controls.Border
        $badge.CornerRadius = '9'; $badge.Padding = '8,1'; $badge.VerticalAlignment = 'Top'; $badge.Visibility = 'Collapsed'
        Use-Res $badge $BG 'Accent'
        $badgeText = New-Object Windows.Controls.TextBlock
        $badgeText.FontSize = 11; Use-Res $badgeText $FG 'OnAccent'
        $badge.Child = $badgeText
        [Windows.Controls.DockPanel]::SetDock($badge, 'Right')
        $icon = New-Object Windows.Controls.TextBlock
        $g = if ($glyphs.ContainsKey($cat)) { $glyphs[$cat] } else { 0xE71D }
        $icon.Text = [string][char]$g
        $icon.FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'; $icon.FontSize = 22
        Use-Res $icon $FG 'AccentText'
        [void]$top.Children.Add($badge); [void]$top.Children.Add($icon)

        $tt = New-Object Windows.Controls.TextBlock
        $tt.Text = "$cat"; $tt.FontSize = 17; $tt.FontWeight = 'SemiBold'; $tt.Margin = '0,6,0,1'; $tt.TextTrimming = 'CharacterEllipsis'
        Use-Res $tt $FG 'Text'
        $sub = New-Object Windows.Controls.TextBlock
        $sub.Text = "$($catApps.Count) apps"; $sub.FontSize = 12
        Use-Res $sub $FG 'Muted'
        [void]$tsp.Children.Add($top); [void]$tsp.Children.Add($tt); [void]$tsp.Children.Add($sub)
        $tile.Child = $tsp
        [void]$tiles.Children.Add($tile)

        $sec = @{ Name = "$cat"; Grid = $grid; Tile = $tile; Sub = $sub; Badge = $badge; BadgeText = $badgeText
                  Checks = New-Object System.Collections.ArrayList; Statuses = New-Object System.Collections.ArrayList }
        # Short hover delay, so moving the mouse across other tiles doesn't switch by accident
        $ht = New-Object Windows.Threading.DispatcherTimer
        $ht.Interval = [TimeSpan]::FromMilliseconds(220)
        $ht.Tag = $sec
        $ht.Add_Tick({ $this.Stop(); if ($this.Tag.Tile.IsMouseOver) { Show-Category $this.Tag } })
        $sec.HoverTimer = $ht
        $tile.Tag = $sec
        $tile.Add_MouseEnter({ Set-TileLook $this.Tag; $this.Tag.HoverTimer.Start() })
        $tile.Add_MouseLeave({ $this.Tag.HoverTimer.Stop(); Set-TileLook $this.Tag })
        $tile.Add_MouseLeftButtonUp({ Show-Category $this.Tag })
        Set-TileLook $sec
        $sections += $sec

        foreach ($a in $catApps) {
            $card = New-Object Windows.Controls.Border
            Use-Res $card $BG 'Card'; Use-Res $card $BRD 'CardBorder'; $card.BorderThickness = '1'
            $card.CornerRadius = '10'; $card.Padding = '12,9'; $card.Margin = '4'
            $dock = New-Object Windows.Controls.DockPanel

            $pill = New-Object Windows.Controls.Border
            $pill.CornerRadius = '10'; $pill.Padding = '9,2'; Use-Res $pill $BG 'WorkBg'
            $pill.VerticalAlignment = 'Center'
            $st = New-Object Windows.Controls.TextBlock
            $st.Text = 'checking'; $st.FontSize = 11; Use-Res $st $FG 'WorkFg'
            $pill.Child = $st
            [Windows.Controls.DockPanel]::SetDock($pill, 'Right')

            $cb = New-Object Windows.Controls.CheckBox
            $cb.Content = $a.name; $cb.IsChecked = [bool]$a.default
            $cb.ToolTip = $(if ($a.id) { $a.id } elseif ($a.ids) { $a.ids -join ', ' } elseif ($a.portable) { $a.portable } elseif ($a.page) { $a.page } else { $a.installer })
            [void]$dock.Children.Add($pill)
            [void]$dock.Children.Add($cb)
            $card.Child = $dock
            # Hover highlight, and clicking anywhere on the card ticks it
            $card.Cursor = 'Hand'
            $card.Tag = $cb
            [void]$sec.Checks.Add($cb)
            [void]$sec.Statuses.Add($st)
            $card.Add_MouseEnter({ Use-Res $this $BG 'CardHover'; Use-Res $this $BRD 'AccentText' })
            $card.Add_MouseLeave({ Use-Res $this $BG 'Card'; Use-Res $this $BRD 'CardBorder' })
            $card.Add_MouseLeftButtonUp({ $this.Tag.IsChecked = -not $this.Tag.IsChecked })
            [void]$grid.Children.Add($card)
            $rows[$(if ($a.id) { $a.id } else { "direct:$($a.name)" })] = @{ Check = $cb; Status = $st; Pill = $pill; App = $a }
        }
    }
    if ($sections.Count) { Show-Category $sections[0] }

    # ---------- Background worker (keeps the window responsive) ----------
    $sync = [hashtable]::Synchronized(@{
        Log      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        Status   = [hashtable]::Synchronized(@{})
        Busy     = $false
        Progress = ''
        StatusBusy = $false
        StatusProgress = ''
        SPS      = $null
        SJob     = $null
        PS       = $null
        Job      = $null
        Winget   = $wingetExe
        RepoRaw  = $RepoRaw
        ScriptUrl = $ScriptUrl
    })

    $Worker = {
        param($sync, $tasks, $mode)
        $progKey = if ($mode -eq 'status') { 'StatusProgress' } else { 'Progress' }

        function Log([string]$m) { $sync.Log.Enqueue(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $m)) }

        $barChars = '[{0}{1}]' -f [char]0x2588, [char]0x2592
        function Invoke-Winget([string[]]$WgArgs, [switch]$Quiet) {
            $clean = New-Object System.Collections.ArrayList
            $global:LASTEXITCODE = $null
            if (-not $Quiet) { Log "    > winget $($WgArgs -join ' ')" }
            try {
                & $sync.Winget @WgArgs 2>&1 | ForEach-Object {
                    $ln = ("$_" -split "`r")[-1].Trim()
                    if ($ln -and $ln -notmatch '^[\-\\|/ ]+$' -and $ln -notmatch $barChars) {
                        [void]$clean.Add($ln)
                        if (-not $Quiet) { $sync.Log.Enqueue("             $ln") }   # live output, like a console
                    }
                }
                $code = $LASTEXITCODE
            } catch {
                [void]$clean.Add("winget failed to run: $($_.Exception.Message)")
                $code = -1
            }
            if ($null -eq $code) { $code = -1 }
            [pscustomobject]@{ Code = $code; Lines = @($clean); Text = (@($clean) -join "`n") }
        }

        $ProgressPreference = 'SilentlyContinue'   # makes downloads much faster in Windows PowerShell

        # Apps that aren't in winget are found through Windows' list of installed programs
        function Find-Uninstall([string]$name) {
            if (-not $name) { return $null }
            $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
            Get-ItemProperty $paths -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "*$name*" } | Select-Object -First 1
        }

        function Get-State($t) {
            if ($t.Portable) {
                if (Get-PortableExe $t) { return 'Installed' } else { return 'Not installed' }
            }
            if (-not $t.Id) {
                if (Find-Uninstall $t.Detect) { return 'Installed' } else { return 'Not installed' }
            }
            $r = Invoke-Winget @('list', '--id', $t.Id, '-e', '--source', 'winget', '--accept-source-agreements') -Quiet
            if ($r.Code -ne 0) { return 'Not installed' }
            $idRx = [regex]::Escape($t.Id)
            $line = $r.Lines | Where-Object { $_ -match "(^|\s)$idRx(\s|$)" } | Select-Object -First 1
            if (-not $line) { return 'Not installed' }
            # after the ID come: installed version [, available version], source
            $after = $line.Substring($line.IndexOf($t.Id) + $t.Id.Length)
            if (([regex]::Matches($after, '\d+(\.\d+)+')).Count -ge 2) { return 'Update available' }
            'Installed'
        }

        # Download a vendor's installer, refuse it unless it carries a valid digital signature, then run it
        function Install-Direct($t) {
            $src = $t.Installer
            $fromGitHub = $src -like 'github:*'
            if ($fromGitHub) {
                $src = Get-GitHubAsset $src.Substring(7) $t.Asset $t.Name
                if (-not $src) { return }
            }
            $fname = [IO.Path]::GetFileName(([uri]$src).AbsolutePath)
            if ([IO.Path]::GetExtension($fname) -notin '.exe', '.msi') { $fname = ($t.Name -replace '[^\w]', '') + '-setup.exe' }
            $file = Join-Path $env:TEMP $fname
            Log "Downloading $($t.Name)..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $ok = $false
            foreach ($u in @($src) + @($t.Mirrors | Where-Object { $_ })) {
                try {
                    Invoke-WebRequest -Uri $u -OutFile $file -UseBasicParsing -ErrorAction Stop
                    $ok = $true; break
                } catch { Log "$($t.Name): download failed from $(([uri]$u).Host): $($_.Exception.Message)" }
            }
            if (-not $ok) {
                if ($t.Url) {
                    Log "$($t.Name): opening its official page instead - download and run it there, then press Refresh."
                    Start-Process $t.Url
                }
                return
            }
            $sig = Get-AuthenticodeSignature $file
            if ($sig.Status -eq 'Valid') {
                $signer = $sig.SignerCertificate.Subject -replace '^CN="?([^,"]+).*', '$1'
            } elseif ($fromGitHub -and $sig.Status -eq 'NotSigned') {
                $signer = 'nobody (not code-signed; downloaded from the project''s official GitHub release)'
            } else {
                Log "$($t.Name): the installer is not validly signed ($($sig.Status)), so it was not run."
                Remove-Item $file -Force -ErrorAction SilentlyContinue
                return
            }
            if ($t.Args) {
                Log "$($t.Name): signed by $signer. Installing silently..."
                Start-Process -FilePath $file -ArgumentList $t.Args -Wait
            } else {
                Log "$($t.Name): signed by $signer. Running the installer - finish its setup window."
                Start-Process -FilePath $file -Wait
            }
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            if (Find-Uninstall $t.Detect) { Log "$($t.Name): installed." } else { Log "$($t.Name): setup closed, but it doesn't show as installed." }
        }

        # Portable apps: a single .exe kept in Program Files, with Start menu and desktop shortcuts
        function Get-PortableDir($t) { Join-Path $env:ProgramFiles ($t.Name -replace '[^\w\- ]', '') }
        function Get-PortableLinks($t) {
            @((Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\$($t.Name).lnk"),
              (Join-Path $env:PUBLIC "Desktop\$($t.Name).lnk"))
        }
        function Stop-Portable($t) {
            Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($t.Exe)) -ErrorAction SilentlyContinue | Stop-Process -Force
            Start-Sleep -Milliseconds 500
        }

        # Newest GitHub release (pre-releases included) with a file matching the pattern
        function Get-GitHubAsset([string]$repo, [string]$pattern, [string]$name) {
            Log "Looking up the latest $name release on GitHub ($repo)..."
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            try {
                $rels = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases?per_page=15" -Headers @{ 'User-Agent' = 'SoftservTools' } -UseBasicParsing -ErrorAction Stop
            } catch { Log "$($name): couldn't reach GitHub: $($_.Exception.Message)"; return $null }
            $asset = @($rels) | Where-Object { -not $_.draft } | ForEach-Object { $_.assets } | Where-Object { $_.name -match $pattern } | Select-Object -First 1
            if (-not $asset) { Log "$($name): no Windows download found in the latest releases."; return $null }
            Log "$($name): found $($asset.name)"
            $asset.browser_download_url
        }

        # The app's .exe inside its folder (zip apps may keep it in a subfolder)
        function Get-PortableExe($t) {
            $dir = Get-PortableDir $t
            if (-not (Test-Path $dir)) { return $null }
            $direct = Join-Path $dir $t.Exe
            if (Test-Path $direct) { return $direct }
            $f = Get-ChildItem $dir -Recurse -Filter $t.Exe -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { $f.FullName } else { $null }
        }

        function Install-Portable($t) {
            $dir = Get-PortableDir $t
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $url = $t.Portable
            if ($url -like 'github:*') {
                $url = Get-GitHubAsset $url.Substring(7) $t.Asset $t.Name
                if (-not $url) { return }
            }
            $isZip = $url -match '\.zip($|\?)'
            $tmp = Join-Path $env:TEMP $(if ($isZip) { (($t.Name -replace '[^\w]', '') + '.zip') } else { $t.Exe })
            Log "Downloading $($t.Name)..."
            try {
                Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -ErrorAction Stop
            } catch { Log "$($t.Name): download failed: $($_.Exception.Message)"; return }

            if ($isZip) {
                Log "$($t.Name): zip from the project's official release page; extracting..."
                Stop-Portable $t
                if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                try { Expand-Archive -Path $tmp -DestinationPath $dir -Force -ErrorAction Stop }
                catch { Log "$($t.Name): couldn't extract: $($_.Exception.Message)"; return }
                finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
            } else {
                $sig = Get-AuthenticodeSignature $tmp
                if ($sig.Status -eq 'Valid') {
                    $signer = $sig.SignerCertificate.Subject -replace '^CN="?([^,"]+).*', '$1'
                    Log "$($t.Name): signed by $signer."
                } elseif ($sig.Status -eq 'NotSigned') {
                    Log "$($t.Name): not digitally signed (normal for this portable build); using the official download link."
                } else {
                    Log "$($t.Name): the file's signature is broken ($($sig.Status)), so it was not installed."
                    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                    return
                }
                Stop-Portable $t
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
                Move-Item $tmp (Join-Path $dir $t.Exe) -Force
            }

            $exe = Get-PortableExe $t
            if (-not $exe) { Log "$($t.Name): $($t.Exe) wasn't found after installing."; return }
            $shell = New-Object -ComObject WScript.Shell
            foreach ($lnkPath in (Get-PortableLinks $t)) {
                $lnk = $shell.CreateShortcut($lnkPath)
                $lnk.TargetPath = $exe
                $lnk.WorkingDirectory = Split-Path $exe
                $lnk.Save()
            }
            Log "$($t.Name): installed to $dir, with Start menu and desktop shortcuts."
        }

        function Uninstall-Portable($t) {
            $dir = Get-PortableDir $t
            if (-not (Test-Path $dir)) { Log "$($t.Name): not installed."; return }
            Log "Uninstalling $($t.Name)..."
            Stop-Portable $t
            Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            Get-PortableLinks $t | Where-Object { Test-Path $_ } | Remove-Item -Force -ErrorAction SilentlyContinue
            if (Test-Path $dir) { Log "$($t.Name): some files are in use; close it and try again." } else { Log "$($t.Name): removed." }
        }

        function Invoke-Uninstaller($u, [string]$extraArgs) {
            if ($u.QuietUninstallString) { $cmd = $u.QuietUninstallString }
            elseif ($u.UninstallString -match 'msiexec') {
                $guid = [regex]::Match($u.UninstallString, '\{[0-9A-Fa-f\-]+\}').Value
                $cmd = "msiexec.exe /x $guid /qb /norestart"
            } else {
                $cmd = $u.UninstallString
                if ($extraArgs) { $cmd = "$cmd $extraArgs" }
            }
            Log "    running: $cmd"
            Start-Process -FilePath cmd.exe -ArgumentList "/c `"$cmd`"" -Wait
        }

        function Uninstall-Direct($t) {
            $u = Find-Uninstall $t.Detect
            if (-not $u) { Log "$($t.Name): not installed."; return }
            Log "Uninstalling $($t.Name)..."
            Invoke-Uninstaller $u $t.UninstallArgs
            if (Find-Uninstall $t.Detect) { Log "$($t.Name): still installed - finish or check its uninstall window." } else { Log "$($t.Name): removed." }
        }

        # winget first; if winget can't, use the app's own uninstaller from Windows' program list
        function Uninstall-Winget($t) {
            Log "Uninstalling $($t.Name)..."
            $r = Invoke-Winget @('uninstall', '--id', $t.Id, '-e', '--silent', '--accept-source-agreements')
            if ($r.Code -eq 0) { Log "$($t.Name): removed."; return }
            if ($r.Code -eq $USER_SCOPE) {
                Log "$($t.Name): it was installed for your Windows user only, so winget won't remove it as admin. Using its own uninstaller instead..."
            } elseif ($r.Code -ne $NOT_FOUND) {
                Log-Failure $t.Name $r
                Log "$($t.Name): trying again with its normal uninstall window..."
                $r2 = Invoke-Winget @('uninstall', '--id', $t.Id, '-e', '--accept-source-agreements')
                if ($r2.Code -eq 0) { Log "$($t.Name): removed."; return }
            }
            # Look it up in Windows' program list: the name winget reported first ("Found Chromium [...]"), then ours
            $names = New-Object System.Collections.ArrayList
            foreach ($ln in $r.Lines) { if ($ln -match '^Found (.+?) \[') { [void]$names.Add($Matches[1].Trim()) } }
            [void]$names.Add($t.Detect); [void]$names.Add($t.Name)
            $u = $null
            foreach ($nm in ($names | Where-Object { $_ } | Select-Object -Unique)) { $u = Find-Uninstall $nm; if ($u) { break } }
            if (-not $u) { Log "$($t.Name): winget and Windows' program list don't show it as installed."; return }
            Log "$($t.Name): using its own uninstaller ($($u.DisplayName))..."
            Invoke-Uninstaller $u ''
            Start-Sleep -Seconds 2
            if (Find-Uninstall $u.DisplayName) { Log "$($t.Name): still installed - finish or check its uninstall window." } else { Log "$($t.Name): removed." }
        }

        function Log-Failure($name, $r) { Log ('{0}: failed (code 0x{1:X8}).' -f $name, $r.Code) }

        $UP_TO_DATE  = -1978335189   # 0x8A15002B no applicable update
        $NOT_FOUND   = -1978335212   # 0x8A150014 no installed package found
        $ALREADY     = -1978335135   # 0x8A150061 already installed
        $USER_SCOPE  = -1978335107   # 0x8A15007D installed for one user; winget won't touch it from an admin session

        try {
            $i = 0; $n = @($tasks).Count
            foreach ($t in $tasks) {
                $i++
                $sync[$progKey] = "($i of $n)"

                # A card that covers several winget packages (e.g. Visual C++ x64 + x86)
                if (@($t.Ids | Where-Object { $_ }).Count) {
                    $verb = @{ install = 'install'; update = 'upgrade'; uninstall = 'uninstall' }[$t.Action]
                    if ($verb) {
                        $sync.Status[$t.Key] = @{ install = 'Installing...'; upgrade = 'Updating...'; uninstall = 'Removing...' }[$verb]
                        Log "$($t.Name): $verb..."
                        foreach ($gid in $t.Ids) {
                            $wa = @($verb, '--id', $gid, '-e', '--silent', '--accept-source-agreements')
                            if ($verb -ne 'uninstall') { $wa += @('--source', 'winget') }
                            if ($verb -ne 'uninstall') { $wa += '--accept-package-agreements' }
                            $r = Invoke-Winget $wa
                            if ($r.Code -eq 0)                           { Log "    $($gid): done." }
                            elseif ($r.Code -in $UP_TO_DATE, $ALREADY)  { Log "    $($gid): already up to date." }
                            elseif ($r.Code -eq $NOT_FOUND)             { Log "    $($gid): not installed." }
                            else                                         { Log-Failure "    $gid" $r }
                        }
                    }
                    $states = @(foreach ($gid in $t.Ids) { Get-State ([pscustomobject]@{ Id = $gid }) })
                    $missing = @($states | Where-Object { $_ -eq 'Not installed' }).Count
                    $sync.Status[$t.Key] = if ($missing -eq $states.Count) { 'Not installed' }
                                           elseif ($missing)                 { 'Partly installed' }
                                           elseif ($states -contains 'Update available') { 'Update available' }
                                           else                              { 'Installed' }
                    continue
                }

                switch ($t.Action) {

                    'shortcut' {
                        # Keep a local copy in a folder only admins can change, and a task that runs it with admin rights.
                        # No hidden window, no download-and-run in the task: just a normal script file.
                        try {
                            $dir   = Join-Path $env:ProgramData 'SoftservTools'
                            $local = Join-Path $dir 'install.ps1'
                            New-Item -ItemType Directory -Path $dir -Force | Out-Null
                            & icacls.exe $dir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null

                            # Refresh the local copy (used from the next launch on)
                            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                            $tmp = "$local.new"
                            Invoke-WebRequest -Uri $sync.ScriptUrl -OutFile $tmp -UseBasicParsing -ErrorAction Stop
                            if ((Get-Item $tmp).Length -gt 20000 -and (Select-String -Path $tmp -Pattern 'function Start-MyApps' -Quiet)) {
                                Move-Item $tmp $local -Force
                            } else { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }

                            $tn  = "SoftservTools-$env:USERNAME"
                            $arg = "-NoProfile -ExecutionPolicy RemoteSigned -WindowStyle Minimized -File `"$local`""
                            $act = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $arg
                            $pri = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
                            $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
                            $old = Get-ScheduledTask -TaskName $tn -ErrorAction SilentlyContinue
                            $isNew = -not $old -or ($old.Actions[0].Arguments -ne $arg)
                            Register-ScheduledTask -TaskName $tn -Action $act -Principal $pri -Settings $set `
                                -Description 'Opens Softserv Tools (from C:\ProgramData\SoftservTools) with admin rights' -Force -ErrorAction Stop | Out-Null

                            # Clean up the task, shortcuts and folder from older names (My Apps, SoftServe Tools)
                            foreach ($oldName in @(@('MyApps', 'My Apps'), @('SoftServeTools', 'SoftServe Tools'))) {
                                Unregister-ScheduledTask -TaskName "$($oldName[0])-$env:USERNAME" -Confirm:$false -ErrorAction SilentlyContinue
                                foreach ($folder in 'Programs', 'Desktop') {
                                    Remove-Item (Join-Path ([Environment]::GetFolderPath($folder)) "$($oldName[1]).lnk") -Force -ErrorAction SilentlyContinue
                                }
                                Remove-Item (Join-Path $env:ProgramData $oldName[0]) -Recurse -Force -ErrorAction SilentlyContinue
                            }

                            $shell = New-Object -ComObject WScript.Shell
                            foreach ($lp in @((Join-Path ([Environment]::GetFolderPath('Programs')) 'Softserv Tools.lnk'),
                                              (Join-Path ([Environment]::GetFolderPath('Desktop'))  'Softserv Tools.lnk'))) {
                                $l = $shell.CreateShortcut($lp)
                                $l.TargetPath   = "$env:SystemRoot\System32\schtasks.exe"
                                $l.Arguments    = "/run /tn `"$tn`""
                                $l.IconLocation = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
                                $l.WindowStyle  = 7
                                $l.Description  = 'Softserv Tools installer'
                                $l.Save()
                            }
                            if ($isNew) { Log 'Shortcut ready: "Softserv Tools" on the desktop and in the Start menu (no UAC prompt).' }
                        } catch { Log "Couldn't set up the Softserv Tools shortcut: $($_.Exception.Message)" }
                    }

                    'wingetcheck' {
                        $r = Invoke-Winget @('--version') -Quiet
                        if ($r.Code -eq 0) { Log "winget $($r.Lines -join ' ')" }
                        else { Log "winget isn't working: $($r.Text)" }
                    }

                    'status' { $sync.Status[$t.Key] = Get-State $t }

                    'statusall' {
                        # Two winget calls for everything, instead of one per app
                        $items = @($t.Items)
                        $installed = $null
                        $tmp = Join-Path $env:TEMP ("sst-export-{0}.json" -f [guid]::NewGuid().ToString('N'))
                        $sync.StatusProgress = '(reading installed apps)'
                        $null = Invoke-Winget @('export', '-o', $tmp, '--source', 'winget', '--include-versions', '--accept-source-agreements') -Quiet
                        if (Test-Path $tmp) {
                            try {
                                $installed = @{}
                                foreach ($src in @((Get-Content $tmp -Raw | ConvertFrom-Json).Sources)) {
                                    foreach ($pk in @($src.Packages)) { $installed[("$($pk.PackageIdentifier)").ToLower()] = $true }
                                }
                            } catch { $installed = $null }
                            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
                        }
                        $upLines = @()
                        if ($installed) {
                            $sync.StatusProgress = '(checking for updates)'
                            $upLines = (Invoke-Winget @('upgrade', '--source', 'winget', '--include-unknown', '--accept-source-agreements') -Quiet).Lines
                        }
                        function Get-FastState([string]$id) {
                            if (-not $installed.ContainsKey($id.ToLower())) { return 'Not installed' }
                            $rx = "(^|\s)$([regex]::Escape($id))(\s|$)"
                            if (@($upLines | Where-Object { $_ -match $rx }).Count) { 'Update available' } else { 'Installed' }
                        }
                        $j = 0
                        foreach ($x in $items) {
                            $j++; $sync.StatusProgress = "($j of $($items.Count))"
                            $gids = @($x.Ids | Where-Object { $_ })
                            if ($gids.Count) {
                                $states = @(foreach ($gid in $gids) { if ($installed) { Get-FastState $gid } else { Get-State ([pscustomobject]@{ Id = $gid }) } })
                                $missing = @($states | Where-Object { $_ -eq 'Not installed' }).Count
                                $sync.Status[$x.Key] = if ($missing -eq $states.Count) { 'Not installed' }
                                                       elseif ($missing) { 'Partly installed' }
                                                       elseif ($states -contains 'Update available') { 'Update available' }
                                                       else { 'Installed' }
                            }
                            elseif ($x.Id -and $installed) { $sync.Status[$x.Key] = Get-FastState $x.Id }
                            else { $sync.Status[$x.Key] = Get-State $x }
                        }
                    }

                    'install' {
                        $sync.Status[$t.Key] = 'Installing...'
                        if ($t.Portable)  { Install-Portable $t; $sync.Status[$t.Key] = Get-State $t; break }
                        if ($t.Page) {
                            Log "$($t.Name): its maker only offers the installer on their website. Opening $($t.Page) - download and run it, then press Refresh."
                            Start-Process $t.Page
                            $sync.Status[$t.Key] = Get-State $t; break
                        }
                        if ($t.Installer) { Install-Direct $t; $sync.Status[$t.Key] = Get-State $t; break }
                        Log "Installing $($t.Name)..."
                        $wa = @('install', '--id', $t.Id, '-e', '--source', 'winget', '--silent',
                                '--accept-package-agreements', '--accept-source-agreements')
                        if ($t.Scope)    { $wa += @('--scope', $t.Scope) }
                        if ($t.Override) { $wa += @('--override', $t.Override) }
                        $r = Invoke-Winget $wa
                        if ($r.Text -match 'hash does not match') {
                            Log "$($t.Name): the vendor's file no longer matches winget's checksum. Opening the official download page instead."
                            if ($t.Url) { Start-Process $t.Url }
                        }
                        elseif ($r.Code -eq 0) { Log "$($t.Name): installed." }
                        elseif ($r.Code -in $UP_TO_DATE, $ALREADY) { Log "$($t.Name): already installed and up to date." }
                        else { Log-Failure $t.Name $r }
                        $sync.Status[$t.Key] = Get-State $t
                    }

                    'update' {
                        $sync.Status[$t.Key] = 'Updating...'
                        if ($t.Portable)  { Install-Portable $t; $sync.Status[$t.Key] = Get-State $t; break }
                        if ($t.Page) {
                            Log "$($t.Name): its maker only offers the installer on their website. Opening $($t.Page) - download and run it, then press Refresh."
                            Start-Process $t.Page
                            $sync.Status[$t.Key] = Get-State $t; break
                        }
                        if ($t.Installer) { Install-Direct $t; $sync.Status[$t.Key] = Get-State $t; break }
                        Log "Updating $($t.Name)..."
                        $wa = @('upgrade', '--id', $t.Id, '-e', '--source', 'winget', '--silent',
                                '--accept-package-agreements', '--accept-source-agreements')
                        if ($t.Scope)    { $wa += @('--scope', $t.Scope) }
                        if ($t.Override) { $wa += @('--override', $t.Override) }
                        $r = Invoke-Winget $wa
                        if ($r.Text -match 'hash does not match') {
                            Log "$($t.Name): checksum mismatch. Opening the official download page instead."
                            if ($t.Url) { Start-Process $t.Url }
                        }
                        elseif ($r.Code -eq 0)          { Log "$($t.Name): updated." }
                        elseif ($r.Code -eq $UP_TO_DATE) { Log "$($t.Name): already up to date." }
                        elseif ($r.Code -eq $USER_SCOPE) { Log "$($t.Name): installed for your user only, so it can't be updated from here. It usually updates itself; or Uninstall and Install it again here to install it for all users." }
                        elseif ($r.Code -eq $NOT_FOUND)  { Log "$($t.Name): not installed, nothing to update." }
                        else { Log-Failure $t.Name $r }
                        $sync.Status[$t.Key] = Get-State $t
                    }

                    'uninstall' {
                        $sync.Status[$t.Key] = 'Removing...'
                        if ($t.Portable)  { Uninstall-Portable $t; $sync.Status[$t.Key] = Get-State $t; break }
                        if ($t.Installer -or $t.Page) { Uninstall-Direct $t; $sync.Status[$t.Key] = Get-State $t; break }
                        Uninstall-Winget $t
                        $sync.Status[$t.Key] = Get-State $t
                    }

                    'updateall' {
                        Log 'Updating every app winget knows about (this can take a while)...'
                        $r = Invoke-Winget @('upgrade', '--all', '--source', 'winget', '--silent',
                                             '--accept-package-agreements', '--accept-source-agreements')
                        $r.Lines | Where-Object { $_ -match 'Successfully|failed|Installing|No installed package|No available upgrade' } |
                            Select-Object -Last 15 | ForEach-Object { Log "    $_" }
                        Log 'Update everything: finished.'
                    }

                    'rdpwarn' {
                        try {
                            $k = 'HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services\Client'
                            New-Item -Path $k -Force | Out-Null
                            New-ItemProperty -Path $k -Name 'RedirectionWarningDialogVersion' -PropertyType DWord -Value 1 -Force | Out-Null
                            Log 'RDP: classic connection warning set (RedirectionWarningDialogVersion = 1). Applies to the next .rdp file you open.'
                        } catch { Log "RDP setting failed: $($_.Exception.Message)" }
                    }

                    'execpolicy' {
                        Log 'Allowing PowerShell scripts for this user (RemoteSigned)...'
                        try { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop } catch {}
                        $cu = Get-ExecutionPolicy -Scope CurrentUser
                        if ("$cu" -eq 'RemoteSigned') { Log 'Done: your own .ps1 scripts now run; downloaded ones must be signed.' }
                        else { Log "Could not change it (CurrentUser is $cu). A Group Policy may be controlling it." }
                        foreach ($gp in 'MachinePolicy', 'UserPolicy') {
                            $v = Get-ExecutionPolicy -Scope $gp
                            if ("$v" -ne 'Undefined') { Log "    Note: $gp is set to $v, which overrides this." }
                        }
                    }

                    'libernt' {
                        try {
                            $dir = Join-Path $env:TEMP 'libernt'
                            New-Item -ItemType Directory -Path $dir -Force | Out-Null
                            $f = Join-Path $dir 'libernt-look.ps1'
                            Log 'Downloading the LiberNT look script...'
                            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                            Invoke-WebRequest -Uri "$($sync.RepoRaw)/libernt-look.ps1" -OutFile $f -UseBasicParsing -ErrorAction Stop
                            Log 'Applying the LiberNT look (Explorer restarts once)...'
                            $out = & powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File $f 2>&1 | ForEach-Object { "$_" }
                            $out | Where-Object { $_ } | Select-Object -Last 6 | ForEach-Object { Log "    $_" }
                            if ($LASTEXITCODE -eq 0) { Log 'LiberNT look applied.' } else { Log "LiberNT script ended with code $LASTEXITCODE." }
                        } catch { Log "LiberNT look failed: $($_.Exception.Message)" }
                    }

                    'restore' {
                        Log 'Creating a restore point...'
                        try {
                            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
                            $w = $null
                            Checkpoint-Computer -Description 'Softserv Tools' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable w -WarningAction SilentlyContinue
                            if ($w) { Log "Restore point: $w" } else { Log 'Restore point created.' }
                        } catch { Log "Restore point failed: $($_.Exception.Message)" }
                    }

                    'edge' {
                        $exe = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
                        if (-not (Test-Path $exe)) { Log 'Microsoft Edge is not installed.'; break }
                        Log 'Removing Microsoft Edge (WebView2 is left alone)...'
                        Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force
                        $sys = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
                        New-Item -ItemType Directory -Path $sys -Force | Out-Null
                        New-Item -ItemType File -Path "$sys\MicrosoftEdge.exe" -Force | Out-Null
                        $setup = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue |
                                 Select-Object -First 1
                        if (-not $setup) { Log 'Edge setup.exe not found.'; break }
                        & $setup.FullName --uninstall --system-level --verbose-logging --force-uninstall
                        for ($s = 0; $s -lt 90 -and (Test-Path $exe); $s += 3) { Start-Sleep -Seconds 3 }
                        if (Test-Path $exe) { Log 'Edge is still there. Check %TEMP%\msedge_installer.log for the reason.' }
                        else { Log 'Microsoft Edge removed.' }
                    }
                }
            }
        }
        catch { Log "Error: $($_.Exception.Message)" }
        finally {
            if ($mode -eq 'status') { $sync.StatusBusy = $false; $sync.StatusProgress = '' }
            else { $sync.Busy = $false; $sync.Progress = '' }
        }
    }

    function Start-Work($tasks) {
        if ($sync.Busy) { $LogBox.AppendText("Still working on the previous task - wait for it to finish.`r`n"); $LogBox.ScrollToEnd(); return }
        $tasks = @($tasks)
        if ($tasks.Count -eq 0) { $LogBox.AppendText("Nothing selected.`r`n"); return }
        $sync.Busy = $true
        $ps = [powershell]::Create()
        [void]$ps.AddScript($Worker).AddArgument($sync).AddArgument($tasks).AddArgument('work')
        $sync.PS  = $ps
        $sync.Job = $ps.BeginInvoke()
    }

    # Status checks run on their own, so the buttons stay usable while they run
    function Start-Status {
        if ($sync.StatusBusy) { return }
        $sync.StatusBusy = $true
        $ps = [powershell]::Create()
        $job = @([pscustomobject]@{ Action = 'statusall'; Items = @(Get-StatusTasks) })
        [void]$ps.AddScript($Worker).AddArgument($sync).AddArgument($job).AddArgument('status')
        $sync.SPS  = $ps
        $sync.SJob = $ps.BeginInvoke()
    }

    function Get-AppKey($app) { if ($app.id) { $app.id } else { "direct:$($app.name)" } }
    function New-Task($action, $app) {
        [pscustomobject]@{ Action = $action; Key = (Get-AppKey $app); Id = $app.id; Name = $app.name
                           Url = $app.homepage; Installer = $(if ($app.githubinstaller) { "github:$($app.githubinstaller)" } else { $app.installer }); Args = $app.args; UninstallArgs = $app.uninstallargs; Portable = $(if ($app.github) { "github:$($app.github)" } else { $app.portable }); Asset = $app.asset; Page = $app.page; Mirrors = @($app.mirrors); Exe = $app.exe; Scope = $app.scope; Override = $app.override; Ids = @($app.ids | Where-Object { $_ }); Detect = $(if ($app.detect) { $app.detect } else { $app.name }) }
    }
    function Get-Selected { @($rows.Values | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.App }) }
    function Get-StatusTasks { @($apps | ForEach-Object { New-Task 'status' $_ }) }
    function Confirm-Action($text) {
        [Windows.MessageBox]::Show($win, $text, 'Softserv Tools', 'YesNo', 'Question') -eq 'Yes'
    }

    # ---------- UI refresh timer ----------
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        $m = $null; $added = $false
        while ($sync.Log.TryDequeue([ref]$m)) { $LogBox.AppendText("$m`r`n"); $added = $true }
        if ($added) { $LogBox.ScrollToEnd() }

        foreach ($id in @($sync.Status.Keys)) {
            if (-not $rows.ContainsKey($id)) { continue }
            $s = $sync.Status[$id]; $lbl = $rows[$id].Status
            if ($lbl.Text -ne $s) {
                $lbl.Text = $s
                $k = switch ($s) { 'Installed' { 'Ok' } 'Update available' { 'Warn' } 'Partly installed' { 'Warn' } 'Not installed' { 'Off' } default { 'Work' } }
                Use-Res $lbl $FG "$($k)Fg"; Use-Res $rows[$id].Pill $BG "$($k)Bg"
            }
        }

        $busy = $sync.Busy
        foreach ($b in $buttons) { $b.IsEnabled = -not $busy }
        $sBusy = $sync.StatusBusy
        $StatusText.Text = if ($busy) { "Working... $($sync.Progress)" } elseif ($sBusy) { "Checking installed apps... $($sync.StatusProgress)" } else { 'Ready' }
        Use-Res $StatusDot $FILL $(if ($busy -or $sBusy) { 'AccentText' } else { 'OkFg' })
        $BusyBar.Visibility = if ($busy -or $sBusy) { 'Visible' } else { 'Collapsed' }
        if (-not $sBusy -and $sync.SPS) {
            try { $sync.SPS.EndInvoke($sync.SJob) | Out-Null } catch {}
            $sync.SPS.Dispose(); $sync.SPS = $null
        }
        $vals = @($rows.Values | ForEach-Object { $_.Status.Text })
        $inst = @($vals | Where-Object { $_ -eq 'Installed' -or $_ -eq 'Update available' }).Count
        $upd  = @($vals | Where-Object { $_ -eq 'Update available' }).Count
        $Summary.Text = "$($rows.Count) apps  |  $inst installed" + $(if ($upd) { "  |  $upd update" + $(if ($upd -gt 1) { 's' } else { '' }) } else { '' })
        foreach ($sc in $sections) {
            $inst = @($sc.Statuses | Where-Object { $_.Text -in 'Installed', 'Update available', 'Partly installed' }).Count
            $sel  = @($sc.Checks | Where-Object { $_.IsChecked }).Count
            $txt  = "$($sc.Checks.Count) apps  |  $inst installed"
            if ($sc.Sub.Text -ne $txt) { $sc.Sub.Text = $txt }
            $sc.BadgeText.Text = "$sel selected"
            $sc.Badge.Visibility = if ($sel) { 'Visible' } else { 'Collapsed' }
        }
        if (-not $busy -and $sync.PS) {
            try { $sync.PS.EndInvoke($sync.Job) | Out-Null } catch {}
            $sync.PS.Dispose(); $sync.PS = $null
            Start-Status   # re-check everything after each action, so the cards stay accurate
        }
    })

    # ---------- Buttons ----------
    $BtnInstall.Add_Click({ Start-Work (Get-Selected | ForEach-Object { New-Task 'install' $_ }) })
    $BtnUpdate.Add_Click({  Start-Work (Get-Selected | ForEach-Object { New-Task 'update'  $_ }) })
    $BtnUninstall.Add_Click({
        $sel = @(Get-Selected)   # @() keeps a single pick as a list, so .Count works
        if ($sel.Count -and (Confirm-Action ("Uninstall these apps?`n`n" + (($sel | ForEach-Object { $_.name }) -join "`n")))) {
            Start-Work ($sel | ForEach-Object { New-Task 'uninstall' $_ })
        }
    })
    $BtnUpdateAll.Add_Click({ Start-Work @([pscustomobject]@{ Action = 'updateall' }) })
    $BtnRefresh.Add_Click({   Start-Status })
    $BtnRefreshTop.Add_Click({ Start-Status })
    $BtnScripts.Add_Click({ Start-Work @([pscustomobject]@{ Action = 'execpolicy' }) })
    $BtnRdp.Add_Click({ Start-Work @([pscustomobject]@{ Action = 'rdpwarn' }) })
    $BtnLiberNT.Add_Click({
        if (Confirm-Action "Apply the LiberNT look to this account?`n`nWallpaper, dark mode, blue accent, clean taskbar and desktop icons. Explorer restarts once.") {
            Start-Work @([pscustomobject]@{ Action = 'libernt' })
        }
    })
    $win.Add_KeyDown({ param($sender, $e) if ($e.Key -eq 'F5') { Start-Status } })
    $BtnRestore.Add_Click({   Start-Work @([pscustomobject]@{ Action = 'restore' }) })
    $BtnEdge.Add_Click({
        if (Confirm-Action "Remove Microsoft Edge?`n`nWebView2 stays installed because other apps need it.") {
            Start-Work @([pscustomobject]@{ Action = 'edge' })
        }
    })
    $LinkAll.Add_MouseLeftButtonUp({  foreach ($r in $rows.Values) { $r.Check.IsChecked = $true } })
    $LinkNone.Add_MouseLeftButtonUp({ foreach ($r in $rows.Values) { $r.Check.IsChecked = $false } })
    $LinkExpand.Add_MouseLeftButtonUp({ Show-AllApps })
    # Log size: Small (default) -> Big -> Hidden -> Small
    $LinkLog.Add_MouseLeftButtonUp({
        switch ([int]$LogPanel.Height) {
            78      { $LogPanel.Height = 260; $LogPanel.Visibility = 'Visible';   $LinkLog.Text = 'Hide log' }
            260     { $LogPanel.Height = 0;   $LogPanel.Visibility = 'Collapsed'; $LinkLog.Text = 'Show log' }
            default { $LogPanel.Height = 78;  $LogPanel.Visibility = 'Visible';   $LinkLog.Text = 'Bigger log' }
        }
        $LogBox.ScrollToEnd()
    })


    $win.Add_Closing({
        param($sender, $e)
        if ($sync.Busy -and -not (Confirm-Action 'Still working. Close anyway?')) { $e.Cancel = $true }
    })
    $win.Add_Loaded({
        $LogBox.AppendText("Loaded $($apps.Count) apps. Checking what's installed...`r`n")
        Start-Work @([pscustomobject]@{ Action = 'wingetcheck' }, [pscustomobject]@{ Action = 'shortcut' })
        Start-Status
    })

    $timer.Start()
    [void]$win.ShowDialog()
    $timer.Stop()
}

Start-MyApps
