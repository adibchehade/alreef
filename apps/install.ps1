<#
    My Apps - a small winget GUI to install, update and remove my usual apps.

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
        $cmd = if ($PSCommandPath) { "& '$PSCommandPath'" } else { "irm '$ScriptUrl' | iex" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-Command', $cmd)
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
        [Windows.MessageBox]::Show("winget could not be installed automatically.`n`nDownload App Installer from https://aka.ms/getwinget, open it, then run this again.", 'My Apps') | Out-Null
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
        Title="My Apps" Width="1060" Height="940" MinWidth="760" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#12151B" Foreground="#E6EAF0"
        FontFamily="Segoe UI" FontSize="13" UseLayoutRounding="True">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#E6EAF0"/>
      <Setter Property="Background" Value="#1E242E"/>
      <Setter Property="BorderBrush" Value="#2C3440"/>
      <Setter Property="Padding" Value="16,9"/>
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
                <Setter TargetName="Bd" Property="BorderBrush" Value="#00ACFF"/>
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
      <Setter Property="Background" Value="#00ACFF"/>
      <Setter Property="BorderBrush" Value="#00ACFF"/>
      <Setter Property="Foreground" Value="#04131E"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Foreground" Value="#FF8A93"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E6EAF0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="18" Height="18" CornerRadius="5" BorderThickness="1.5"
                      BorderBrush="#4A5466" Background="Transparent" VerticalAlignment="Center">
                <Path x:Name="Tick" Data="M3,8 L6.5,11.5 L12.5,4.5" Stroke="#04131E" StrokeThickness="2.2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="11,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Box" Property="BorderBrush" Value="#00ACFF"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="#00ACFF"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="#00ACFF"/>
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
                      <Border CornerRadius="4" Background="#353E4C"/>
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
      <RowDefinition Height="130"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <DockPanel Grid.Row="0" Margin="0,0,0,16">
      <Border Width="44" Height="44" CornerRadius="12" Background="#00ACFF" Margin="0,0,14,0" VerticalAlignment="Center">
        <Path Data="M22,11 L22,27 M15,21 L22,28 L29,21 M14,33 L30,33" Stroke="#04131E" StrokeThickness="2.6"
              StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
      </Border>
      <Border DockPanel.Dock="Right" Background="#1A1F27" BorderBrush="#2C3440" BorderThickness="1"
              CornerRadius="16" Padding="14,6" VerticalAlignment="Center">
        <TextBlock x:Name="Summary" Text="Checking..." Foreground="#8B95A5" FontSize="12"/>
      </Border>
      <Button x:Name="BtnRefreshTop" DockPanel.Dock="Right" Content="Refresh" Margin="0,0,10,0"
              Padding="16,7" VerticalAlignment="Center" ToolTip="Re-check what's installed (F5)"/>
      <StackPanel VerticalAlignment="Center">
        <TextBlock Text="My Apps" FontSize="24" FontWeight="SemiBold"/>
        <TextBlock Text="Tick the apps, then choose an action. Installs come from winget or the vendor's signed installer."
                   Foreground="#8B95A5" Margin="0,2,0,0"/>
      </StackPanel>
    </DockPanel>

    <Border Grid.Row="1" Background="#171B22" BorderBrush="#232A35" BorderThickness="1" CornerRadius="14" Padding="14,4,8,12">
      <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
        <StackPanel x:Name="AppPanel" Margin="0,0,6,0"/>
      </ScrollViewer>
    </Border>

    <WrapPanel Grid.Row="2" Margin="0,16,0,6">
      <Button x:Name="BtnInstall"   Content="Install selected" Style="{StaticResource Primary}"/>
      <Button x:Name="BtnUpdate"    Content="Update selected"/>
      <Button x:Name="BtnUninstall" Content="Uninstall selected" Style="{StaticResource Danger}"/>
      <Button x:Name="BtnUpdateAll" Content="Update everything on this PC"/>
      <Button x:Name="BtnRefresh"   Content="Refresh status"/>
      <Button x:Name="BtnRestore"   Content="Create restore point"/>
      <Button x:Name="BtnEdge"      Content="Remove Edge" Style="{StaticResource Danger}"/>
    </WrapPanel>

    <Border Grid.Row="3" Background="#0D1015" BorderBrush="#232A35" BorderThickness="1" CornerRadius="12" Padding="4">
      <TextBox x:Name="LogBox" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
               FontFamily="Cascadia Mono, Consolas" FontSize="12" Background="Transparent" Foreground="#AEB7C4"
               BorderThickness="0" Padding="8,6"/>
    </Border>

    <DockPanel Grid.Row="4" Margin="2,10,2,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
        <TextBlock x:Name="LinkAll"  Text="Select all"  Foreground="#00ACFF" Cursor="Hand" Margin="0,0,16,0"/>
        <TextBlock x:Name="LinkNone" Text="Select none" Foreground="#00ACFF" Cursor="Hand"/>
      </StackPanel>
      <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="#3DDC97" Margin="0,0,8,0" VerticalAlignment="Center"/>
      <TextBlock x:Name="StatusText" Text="Ready" Foreground="#8B95A5"/>
    </DockPanel>
  </Grid>
</Window>
'@
    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    foreach ($n in 'AppPanel','BtnInstall','BtnUpdate','BtnUninstall','BtnUpdateAll','BtnRefresh','BtnRestore','BtnEdge','LogBox','LinkAll','LinkNone','StatusText','StatusDot','Summary','BtnRefreshTop') {
        Set-Variable -Name $n -Value $win.FindName($n)
    }
    $buttons = @($BtnRefreshTop, $BtnInstall, $BtnUpdate, $BtnUninstall, $BtnUpdateAll, $BtnRefresh, $BtnRestore, $BtnEdge)

    # Open as large as the screen allows
    $wa = [System.Windows.SystemParameters]::WorkArea
    $win.Width  = [Math]::Min(1060, $wa.Width  - 40)
    $win.Height = [Math]::Min(1000, $wa.Height - 40)
    $win.WindowState = 'Maximized'   # open full screen; Restore Down returns to the size above

    # Status pill colours: text, background
    $pillColors = @{
        'Installed'        = @('#3DDC97', '#14302A')
        'Update available' = @('#FFB547', '#3A2D14')
        'Partly installed' = @('#FFB547', '#3A2D14')
        'Not installed'    = @('#8B95A5', '#222833')
    }
    $workingColors = @('#00ACFF', '#0E2C40')

    # ---------- App rows (two columns per category) ----------
    $rows = @{}
    foreach ($cat in ($apps | ForEach-Object { $_.category } | Select-Object -Unique)) {
        $hdr = New-Object Windows.Controls.TextBlock
        $hdr.Text = "$cat".ToUpper(); $hdr.FontSize = 11; $hdr.FontWeight = 'SemiBold'
        $hdr.Foreground = '#00ACFF'; $hdr.Margin = '4,14,0,6'
        [void]$AppPanel.Children.Add($hdr)

        $grid = New-Object Windows.Controls.Primitives.UniformGrid
        $grid.Columns = 2
        [void]$AppPanel.Children.Add($grid)

        foreach ($a in @($apps | Where-Object { $_.category -eq $cat })) {
            $card = New-Object Windows.Controls.Border
            $card.Background = '#1E242E'; $card.BorderBrush = '#262E3A'; $card.BorderThickness = '1'
            $card.CornerRadius = '10'; $card.Padding = '12,9'; $card.Margin = '4'
            $dock = New-Object Windows.Controls.DockPanel

            $pill = New-Object Windows.Controls.Border
            $pill.CornerRadius = '10'; $pill.Padding = '9,2'; $pill.Background = $workingColors[1]
            $pill.VerticalAlignment = 'Center'
            $st = New-Object Windows.Controls.TextBlock
            $st.Text = 'checking'; $st.FontSize = 11; $st.Foreground = $workingColors[0]
            $pill.Child = $st
            [Windows.Controls.DockPanel]::SetDock($pill, 'Right')

            $cb = New-Object Windows.Controls.CheckBox
            $cb.Content = $a.name; $cb.IsChecked = [bool]$a.default
            $cb.ToolTip = $(if ($a.id) { $a.id } elseif ($a.ids) { $a.ids -join ', ' } else { $a.installer })
            [void]$dock.Children.Add($pill)
            [void]$dock.Children.Add($cb)
            $card.Child = $dock
            [void]$grid.Children.Add($card)
            $rows[$(if ($a.id) { $a.id } else { "direct:$($a.name)" })] = @{ Check = $cb; Status = $st; Pill = $pill; App = $a }
        }
    }

    # ---------- Background worker (keeps the window responsive) ----------
    $sync = [hashtable]::Synchronized(@{
        Log      = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
        Status   = [hashtable]::Synchronized(@{})
        Busy     = $false
        Progress = ''
        PS       = $null
        Job      = $null
        Winget   = $wingetExe
    })

    $Worker = {
        param($sync, $tasks)

        function Log([string]$m) { $sync.Log.Enqueue(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $m)) }

        $barChars = '[{0}{1}]' -f [char]0x2588, [char]0x2592
        function Invoke-Winget([string[]]$WgArgs) {
            $global:LASTEXITCODE = $null
            try {
                $lines = & $sync.Winget @WgArgs 2>&1 | ForEach-Object { "$_" }
                $code  = $LASTEXITCODE
            } catch {
                $lines = @("winget failed to run: $($_.Exception.Message)")
                $code  = -1
            }
            if ($null -eq $code) { $code = -1 }
            $clean = foreach ($l in $lines) {
                $t = ($l -split "`r")[-1].Trim()
                if ($t -and $t -notmatch '^[\-\\|/ ]+$' -and $t -notmatch $barChars) { $t }
            }
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
            if (-not $t.Id) {
                if (Find-Uninstall $t.Detect) { return 'Installed' } else { return 'Not installed' }
            }
            $r = Invoke-Winget @('list', '--id', $t.Id, '-e', '--source', 'winget', '--accept-source-agreements')
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
            $file = Join-Path $env:TEMP ([IO.Path]::GetFileName(([uri]$t.Installer).AbsolutePath))
            Log "Downloading $($t.Name)..."
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $t.Installer -OutFile $file -UseBasicParsing -ErrorAction Stop
            } catch { Log "$($t.Name): download failed: $($_.Exception.Message)"; return }
            $sig = Get-AuthenticodeSignature $file
            if ($sig.Status -ne 'Valid') {
                Log "$($t.Name): the installer is not validly signed ($($sig.Status)), so it was not run."
                Remove-Item $file -Force -ErrorAction SilentlyContinue
                return
            }
            $signer = $sig.SignerCertificate.Subject -replace '^CN="?([^,"]+).*', '$1'
            Log "$($t.Name): signed by $signer. Running the installer - finish its setup window."
            Start-Process -FilePath $file -Wait
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            if (Find-Uninstall $t.Detect) { Log "$($t.Name): installed." } else { Log "$($t.Name): setup closed, but it doesn't show as installed." }
        }

        function Uninstall-Direct($t) {
            $u = Find-Uninstall $t.Detect
            if (-not $u) { Log "$($t.Name): not installed."; return }
            $cmd = if ($u.QuietUninstallString) { $u.QuietUninstallString } else { $u.UninstallString }
            Log "Uninstalling $($t.Name)..."
            Start-Process -FilePath cmd.exe -ArgumentList "/c `"$cmd`"" -Wait
            if (Find-Uninstall $t.Detect) { Log "$($t.Name): still installed." } else { Log "$($t.Name): removed." }
        }

        function Log-Failure($name, $r) {
            Log ('{0}: failed (code 0x{1:X8}).' -f $name, $r.Code)
            $r.Lines | Select-Object -Last 3 | ForEach-Object { Log "    $_" }
        }

        $UP_TO_DATE  = -1978335189   # 0x8A15002B no applicable update
        $NOT_FOUND   = -1978335212   # 0x8A150014 no installed package found
        $ALREADY     = -1978335135   # 0x8A150061 already installed

        try {
            $i = 0; $n = @($tasks).Count
            foreach ($t in $tasks) {
                $i++
                $sync.Progress = "($i of $n)"

                # A card that covers several winget packages (e.g. Visual C++ x64 + x86)
                if (@($t.Ids | Where-Object { $_ }).Count) {
                    $verb = @{ install = 'install'; update = 'upgrade'; uninstall = 'uninstall' }[$t.Action]
                    if ($verb) {
                        $sync.Status[$t.Key] = @{ install = 'Installing...'; upgrade = 'Updating...'; uninstall = 'Removing...' }[$verb]
                        Log "$($t.Name): $verb..."
                        foreach ($gid in $t.Ids) {
                            $wa = @($verb, '--id', $gid, '-e', '--source', 'winget', '--silent', '--accept-source-agreements')
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

                    'wingetcheck' {
                        $r = Invoke-Winget @('--version')
                        if ($r.Code -eq 0) { Log "winget $($r.Lines -join ' ')" }
                        else { Log "winget isn't working: $($r.Text)" }
                    }

                    'status' { $sync.Status[$t.Key] = Get-State $t }

                    'install' {
                        $sync.Status[$t.Key] = 'Installing...'
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
                        elseif ($r.Code -eq $NOT_FOUND)  { Log "$($t.Name): not installed, nothing to update." }
                        else { Log-Failure $t.Name $r }
                        $sync.Status[$t.Key] = Get-State $t
                    }

                    'uninstall' {
                        $sync.Status[$t.Key] = 'Removing...'
                        if ($t.Installer) { Uninstall-Direct $t; $sync.Status[$t.Key] = Get-State $t; break }
                        Log "Uninstalling $($t.Name)..."
                        $r = Invoke-Winget @('uninstall', '--id', $t.Id, '-e', '--source', 'winget', '--silent', '--accept-source-agreements')
                        if ($r.Code -eq 0)              { Log "$($t.Name): removed." }
                        elseif ($r.Code -eq $NOT_FOUND) { Log "$($t.Name): not installed." }
                        else { Log-Failure $t.Name $r }
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

                    'restore' {
                        Log 'Creating a restore point...'
                        try {
                            Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
                            $w = $null
                            Checkpoint-Computer -Description 'My Apps' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningVariable w -WarningAction SilentlyContinue
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
        finally { $sync.Busy = $false; $sync.Progress = '' }
    }

    function Start-Work($tasks) {
        if ($sync.Busy) { return }
        $tasks = @($tasks)
        if ($tasks.Count -eq 0) { $LogBox.AppendText("Nothing selected.`r`n"); return }
        $sync.Busy = $true
        $ps = [powershell]::Create()
        [void]$ps.AddScript($Worker).AddArgument($sync).AddArgument($tasks)
        $sync.PS  = $ps
        $sync.Job = $ps.BeginInvoke()
    }

    function Get-AppKey($app) { if ($app.id) { $app.id } else { "direct:$($app.name)" } }
    function New-Task($action, $app) {
        [pscustomobject]@{ Action = $action; Key = (Get-AppKey $app); Id = $app.id; Name = $app.name
                           Url = $app.homepage; Installer = $app.installer; Scope = $app.scope; Override = $app.override; Ids = @($app.ids | Where-Object { $_ }); Detect = $(if ($app.detect) { $app.detect } else { $app.name }) }
    }
    function Get-Selected { @($rows.Values | Where-Object { $_.Check.IsChecked } | ForEach-Object { $_.App }) }
    function Get-StatusTasks { @($apps | ForEach-Object { New-Task 'status' $_ }) }
    function Confirm-Action($text) {
        [Windows.MessageBox]::Show($win, $text, 'My Apps', 'YesNo', 'Question') -eq 'Yes'
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
                $c = if ($pillColors.ContainsKey($s)) { $pillColors[$s] } else { $workingColors }
                $lbl.Foreground = $c[0]; $rows[$id].Pill.Background = $c[1]
            }
        }

        $busy = $sync.Busy
        foreach ($b in $buttons) { $b.IsEnabled = -not $busy }
        $StatusText.Text = if ($busy) { "Working... $($sync.Progress)" } else { 'Ready' }
        $StatusDot.Fill  = if ($busy) { '#00ACFF' } else { '#3DDC97' }
        $vals = @($rows.Values | ForEach-Object { $_.Status.Text })
        $inst = @($vals | Where-Object { $_ -eq 'Installed' -or $_ -eq 'Update available' }).Count
        $upd  = @($vals | Where-Object { $_ -eq 'Update available' }).Count
        $Summary.Text = "$($rows.Count) apps  |  $inst installed" + $(if ($upd) { "  |  $upd update" + $(if ($upd -gt 1) { 's' } else { '' }) } else { '' })
        if (-not $busy -and $sync.PS) {
            try { $sync.PS.EndInvoke($sync.Job) | Out-Null } catch {}
            $sync.PS.Dispose(); $sync.PS = $null
        }
    })

    # ---------- Buttons ----------
    $BtnInstall.Add_Click({ Start-Work (Get-Selected | ForEach-Object { New-Task 'install' $_ }) })
    $BtnUpdate.Add_Click({  Start-Work (Get-Selected | ForEach-Object { New-Task 'update'  $_ }) })
    $BtnUninstall.Add_Click({
        $sel = Get-Selected
        if ($sel.Count -and (Confirm-Action ("Uninstall these apps?`n`n" + (($sel | ForEach-Object { $_.name }) -join "`n")))) {
            Start-Work ($sel | ForEach-Object { New-Task 'uninstall' $_ })
        }
    })
    $BtnUpdateAll.Add_Click({ Start-Work (@([pscustomobject]@{ Action = 'updateall' }) + (Get-StatusTasks)) })
    $BtnRefresh.Add_Click({   Start-Work (Get-StatusTasks) })
    $BtnRefreshTop.Add_Click({ Start-Work (Get-StatusTasks) })
    $win.Add_KeyDown({ param($sender, $e) if ($e.Key -eq 'F5') { Start-Work (Get-StatusTasks) } })
    $BtnRestore.Add_Click({   Start-Work @([pscustomobject]@{ Action = 'restore' }) })
    $BtnEdge.Add_Click({
        if (Confirm-Action "Remove Microsoft Edge?`n`nWebView2 stays installed because other apps need it.") {
            Start-Work @([pscustomobject]@{ Action = 'edge' })
        }
    })
    $LinkAll.Add_MouseLeftButtonUp({  foreach ($r in $rows.Values) { $r.Check.IsChecked = $true } })
    $LinkNone.Add_MouseLeftButtonUp({ foreach ($r in $rows.Values) { $r.Check.IsChecked = $false } })

    $win.Add_Closing({
        param($sender, $e)
        if ($sync.Busy -and -not (Confirm-Action 'Still working. Close anyway?')) { $e.Cancel = $true }
    })
    $win.Add_Loaded({
        $LogBox.AppendText("Loaded $($apps.Count) apps. Checking what's installed...`r`n")
        Start-Work (@([pscustomobject]@{ Action = 'wingetcheck' }) + (Get-StatusTasks))
    })

    $timer.Start()
    [void]$win.ShowDialog()
    $timer.Stop()
}

Start-MyApps
