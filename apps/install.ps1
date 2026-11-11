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

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        [Windows.MessageBox]::Show('winget was not found. Install "App Installer" from the Microsoft Store, then run this again.', 'My Apps') | Out-Null
        return
    }

    # ---------- App list: local apps.json > GitHub apps.json > built-in fallback ----------
    $DefaultAppsJson = @'
[
  { "name": "LibreWolf", "id": "LibreWolf.LibreWolf",      "category": "Browsers",      "homepage": "https://librewolf.net",                       "default": true },
  { "name": "Telegram",  "id": "Telegram.TelegramDesktop", "category": "Communication", "homepage": "https://desktop.telegram.org",                "default": true },
  { "name": "7-Zip",     "id": "7zip.7zip",                "category": "Utilities",     "homepage": "https://www.7-zip.org",                       "default": true },
  { "name": "CCleaner",  "id": "Piriform.CCleaner",        "category": "Utilities",     "homepage": "https://www.ccleaner.com/ccleaner/download", "default": true }
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
        Title="My Apps" Width="820" Height="700" MinWidth="640" MinHeight="540"
        WindowStartupLocation="CenterScreen" Background="#1E1F24" Foreground="#E8E8EC"
        FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Padding" Value="14,7"/>
      <Setter Property="Background" Value="#2D2F37"/>
      <Setter Property="Foreground" Value="#E8E8EC"/>
      <Setter Property="BorderBrush" Value="#3C3F49"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#E8E8EC"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
  </Window.Resources>
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="170"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,12">
      <TextBlock Text="My Apps" FontSize="22" FontWeight="SemiBold"/>
      <TextBlock Text="Tick the apps, then choose an action. Everything comes from the official winget source."
                 Foreground="#9A9CA8" Margin="0,2,0,0"/>
    </StackPanel>

    <Border Grid.Row="1" Background="#26282F" CornerRadius="8" Padding="14,6,14,10">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="AppPanel"/>
      </ScrollViewer>
    </Border>

    <WrapPanel Grid.Row="2" Margin="0,12,0,4">
      <Button x:Name="BtnInstall"   Content="Install selected" Background="#3B6FE0" BorderBrush="#3B6FE0" Foreground="White"/>
      <Button x:Name="BtnUpdate"    Content="Update selected"/>
      <Button x:Name="BtnUninstall" Content="Uninstall selected"/>
      <Button x:Name="BtnUpdateAll" Content="Update everything on this PC"/>
      <Button x:Name="BtnRefresh"   Content="Refresh status"/>
      <Button x:Name="BtnRestore"   Content="Create restore point"/>
      <Button x:Name="BtnEdge"      Content="Remove Edge"/>
    </WrapPanel>

    <TextBox Grid.Row="3" x:Name="LogBox" IsReadOnly="True" TextWrapping="Wrap"
             VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12"
             Background="#14151A" Foreground="#C9CBD3" BorderBrush="#3C3F49" Padding="8"/>

    <DockPanel Grid.Row="4" Margin="0,8,0,0">
      <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
        <TextBlock x:Name="LinkAll"  Text="Select all"  Foreground="#7AA2F7" Cursor="Hand" Margin="0,0,14,0"/>
        <TextBlock x:Name="LinkNone" Text="Select none" Foreground="#7AA2F7" Cursor="Hand"/>
      </StackPanel>
      <TextBlock x:Name="StatusText" Text="Ready" Foreground="#9A9CA8"/>
    </DockPanel>
  </Grid>
</Window>
'@
    $win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
    foreach ($n in 'AppPanel','BtnInstall','BtnUpdate','BtnUninstall','BtnUpdateAll','BtnRefresh','BtnRestore','BtnEdge','LogBox','LinkAll','LinkNone','StatusText') {
        Set-Variable -Name $n -Value $win.FindName($n)
    }
    $buttons = @($BtnInstall, $BtnUpdate, $BtnUninstall, $BtnUpdateAll, $BtnRefresh, $BtnRestore, $BtnEdge)

    # ---------- App rows ----------
    $rows = @{}
    foreach ($cat in ($apps | ForEach-Object { $_.category } | Select-Object -Unique)) {
        $hdr = New-Object Windows.Controls.TextBlock
        $hdr.Text = "$cat".ToUpper(); $hdr.FontSize = 11; $hdr.FontWeight = 'SemiBold'
        $hdr.Foreground = '#7F8290'; $hdr.Margin = '0,10,0,4'
        [void]$AppPanel.Children.Add($hdr)

        foreach ($a in @($apps | Where-Object { $_.category -eq $cat })) {
            $dock = New-Object Windows.Controls.DockPanel
            $dock.Margin = '0,3,0,3'
            $st = New-Object Windows.Controls.TextBlock
            $st.Text = 'checking...'; $st.Foreground = '#7F8290'
            [Windows.Controls.DockPanel]::SetDock($st, 'Right')
            $cb = New-Object Windows.Controls.CheckBox
            $cb.Content = $a.name; $cb.IsChecked = [bool]$a.default; $cb.ToolTip = $a.id
            [void]$dock.Children.Add($st)
            [void]$dock.Children.Add($cb)
            [void]$AppPanel.Children.Add($dock)
            $rows[$a.id] = @{ Check = $cb; Status = $st; App = $a }
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
    })

    $Worker = {
        param($sync, $tasks)

        function Log([string]$m) { $sync.Log.Enqueue(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $m)) }

        $barChars = '[{0}{1}]' -f [char]0x2588, [char]0x2592
        function Invoke-Winget([string[]]$WgArgs) {
            $lines = & winget @WgArgs 2>&1 | ForEach-Object { "$_" }
            $code  = $LASTEXITCODE
            $clean = foreach ($l in $lines) {
                $t = ($l -split "`r")[-1].Trim()
                if ($t -and $t -notmatch '^[\-\\|/ ]+$' -and $t -notmatch $barChars) { $t }
            }
            [pscustomobject]@{ Code = $code; Lines = @($clean); Text = (@($clean) -join "`n") }
        }

        function Get-State([string]$id) {
            $r = Invoke-Winget @('list', '--id', $id, '-e', '--source', 'winget', '--accept-source-agreements')
            if ($r.Code -ne 0) { return 'Not installed' }
            if ($r.Text -match '\bAvailable\b') { return 'Update available' }
            'Installed'
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
                switch ($t.Action) {

                    'status' { $sync.Status[$t.Id] = Get-State $t.Id }

                    'install' {
                        Log "Installing $($t.Name)..."
                        $sync.Status[$t.Id] = 'Installing...'
                        $r = Invoke-Winget @('install', '--id', $t.Id, '-e', '--source', 'winget', '--silent',
                                             '--accept-package-agreements', '--accept-source-agreements')
                        if ($r.Text -match 'hash does not match') {
                            Log "$($t.Name): the vendor's file no longer matches winget's checksum. Opening the official download page instead."
                            if ($t.Url) { Start-Process $t.Url }
                        }
                        elseif ($r.Code -eq 0) { Log "$($t.Name): installed." }
                        elseif ($r.Code -in $UP_TO_DATE, $ALREADY) { Log "$($t.Name): already installed and up to date." }
                        else { Log-Failure $t.Name $r }
                        $sync.Status[$t.Id] = Get-State $t.Id
                    }

                    'update' {
                        Log "Updating $($t.Name)..."
                        $sync.Status[$t.Id] = 'Updating...'
                        $r = Invoke-Winget @('upgrade', '--id', $t.Id, '-e', '--source', 'winget', '--silent',
                                             '--accept-package-agreements', '--accept-source-agreements')
                        if ($r.Text -match 'hash does not match') {
                            Log "$($t.Name): checksum mismatch. Opening the official download page instead."
                            if ($t.Url) { Start-Process $t.Url }
                        }
                        elseif ($r.Code -eq 0)          { Log "$($t.Name): updated." }
                        elseif ($r.Code -eq $UP_TO_DATE) { Log "$($t.Name): already up to date." }
                        elseif ($r.Code -eq $NOT_FOUND)  { Log "$($t.Name): not installed, nothing to update." }
                        else { Log-Failure $t.Name $r }
                        $sync.Status[$t.Id] = Get-State $t.Id
                    }

                    'uninstall' {
                        Log "Uninstalling $($t.Name)..."
                        $sync.Status[$t.Id] = 'Removing...'
                        $r = Invoke-Winget @('uninstall', '--id', $t.Id, '-e', '--source', 'winget', '--silent', '--accept-source-agreements')
                        if ($r.Code -eq 0)              { Log "$($t.Name): removed." }
                        elseif ($r.Code -eq $NOT_FOUND) { Log "$($t.Name): not installed." }
                        else { Log-Failure $t.Name $r }
                        $sync.Status[$t.Id] = Get-State $t.Id
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

    function New-Task($action, $app) {
        [pscustomobject]@{ Action = $action; Id = $app.id; Name = $app.name; Url = $app.homepage }
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
                $lbl.Foreground = switch ($s) {
                    'Installed'        { '#6CCB8A' }
                    'Update available' { '#E5B567' }
                    'Not installed'    { '#7F8290' }
                    default            { '#7AA2F7' }
                }
            }
        }

        $busy = $sync.Busy
        foreach ($b in $buttons) { $b.IsEnabled = -not $busy }
        $StatusText.Text = if ($busy) { "Working... $($sync.Progress)" } else { 'Ready' }
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
        Start-Work (Get-StatusTasks)
    })

    $timer.Start()
    [void]$win.ShowDialog()
    $timer.Stop()
}

Start-MyApps
