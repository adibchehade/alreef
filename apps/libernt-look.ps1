<#
.SYNOPSIS
    Gives Windows 11 / Tiny11 the LiberNT look: BlueHorizon wallpaper, dark mode,
    deep-blue accent on a navy taskbar, centred (or left) Start, clean taskbar,
    classic desktop icons (This PC, Documents, Network, Recycle Bin).

.DESCRIPTION
    Two ways to use it:

    1) Bake into a Tiny11 ISO (run on your PC, as Administrator):
         .\libernt-look.ps1 -Iso "C:\tiny11builder\tiny11.iso"
       Produces tiny11-libernt.iso next to the source ISO. Every new user
       gets the look automatically at first sign-in.

    2) Apply to the Windows you are signed in to right now:
         .\libernt-look.ps1
       (No admin needed. Explorer restarts once.)

    The wallpaper is downloaded from the LiberNT GitHub repository
    (modules/wallpapers/BlueHorizon.png) unless BlueHorizon.png already sits
    next to this script. The image's licence is not recorded in that repository,
    so use it for your own machines only.

.PARAMETER Iso
    Path to a finished Tiny11 (or any Windows 11) ISO to bake the look into.

.PARAMETER OutIso
    Where to write the new ISO. Default: <source name>-libernt.iso beside the source.

.PARAMETER Oscdimg
    Path to oscdimg.exe. Default: searches the Windows ADK, this folder, and the
    folder of the source ISO (Tiny11 Builder leaves oscdimg.exe in its own folder).

.PARAMETER KeepPins
    Keep the apps pinned to the taskbar (LiberNT's taskbar has none).

.PARAMETER StartLeft
    Put Start on the left, as LiberNT does. Default: centred, as in Windows 11.

.PARAMETER AllWallpapers
    Also download LiberNT's other wallpapers into the same folder, so you can pick
    one or run a slideshow in Settings > Personalization > Background. Most of
    them are marked "restricted" in LiberNT's own notes: personal use only.
#>
[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(ParameterSetName = 'Bake', Mandatory = $true)][string]$Iso,
    [Parameter(ParameterSetName = 'Bake')][string]$OutIso,
    [Parameter(ParameterSetName = 'Bake')][string]$Oscdimg,
    [Parameter(ParameterSetName = 'Bake')][string]$WorkDir = "$env:SystemDrive\libernt-work",
    [Parameter(ParameterSetName = 'FirstLogon')][switch]$FirstLogon,
    [switch]$KeepPins,
    [switch]$StartLeft,
    [switch]$AllWallpapers
)

$ErrorActionPreference = 'Stop'
$WallpaperName = 'BlueHorizon.png'
# Pinned to the commit checked on 2026-11-08 so the file can't change underneath you.
$WallpaperUrl  = 'https://raw.githubusercontent.com/LiberNT/LiberNT/d206850033a8182f8da32affd34a314541ae9f08/modules/wallpapers/BlueHorizon.png'
$InstallDir    = 'C:\Windows\LiberNT'   # where the baked image keeps script + wallpaper

# ---------------------------------------------------------------- helpers

function ConvertTo-DWord([string]$hex) {
    # Registry DWORDs are signed in PowerShell; convert 0xFFxxxxxx safely.
    [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$hex), 0)
}

function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Get-Wallpaper([string]$TargetDir) {
    $local = Join-Path $PSScriptRoot $WallpaperName
    $dest  = Join-Path $TargetDir $WallpaperName
    if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
    if ((Test-Path $local) -and ((Resolve-Path $local).Path -ne $dest)) {
        Copy-Item $local $dest -Force
    } elseif (-not (Test-Path $dest)) {
        Write-Host "Downloading LiberNT wallpaper..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $WallpaperUrl -OutFile $dest -UseBasicParsing
    }
    $dest
}

# The rest of LiberNT's wallpaper set (modules/wallpapers in their repository)
$ExtraWallpapers = 'Calm Lake.jpg', 'Feather Droplets.jpg', 'Forest Canopy.jpg', 'Lake Mountains.jpg',
                   'Lugano Reflections.jpg', 'Misty Forest.jpg', 'Modern Villa.jpg', 'Mountain Lake.jpg',
                   'Night Sky.jpg', 'Oil and Water.jpg', 'Plant Textures.jpg', 'Rain Lights.jpg',
                   'Sea Bridge.jpg', 'Sunlit Meadow.jpg'

function Get-AllWallpapers([string]$TargetDir) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $base = $WallpaperUrl.Substring(0, $WallpaperUrl.LastIndexOf('/') + 1)
    foreach ($name in $ExtraWallpapers) {
        $dest = Join-Path $TargetDir $name
        if (Test-Path $dest) { continue }
        Write-Host "Downloading $name..."
        try { Invoke-WebRequest -Uri ($base + [Uri]::EscapeDataString($name)) -OutFile $dest -UseBasicParsing }
        catch { Write-Warning "Could not download ${name}: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------- the look
# $Root is either 'HKCU:' (live) or a loaded Default-user hive (offline image).

function Set-LiberNTLook([string]$Root, [string]$WallpaperPath) {

    # Wallpaper: BlueHorizon, "Fill"
    $desk = "$Root\Control Panel\Desktop"
    Set-Reg $desk 'Wallpaper'        $WallpaperPath 'String'
    Set-Reg $desk 'WallpaperStyle'   '10'           'String'
    Set-Reg $desk 'TileWallpaper'    '0'            'String'
    Set-Reg $desk 'AutoColorization' 0

    # Dark mode, transparency on, accent colour on Start and taskbar
    $pers = "$Root\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
    Set-Reg $pers 'AppsUseLightTheme'   0
    Set-Reg $pers 'SystemUsesLightTheme' 0
    Set-Reg $pers 'EnableTransparency'  1
    Set-Reg $pers 'ColorPrevalence'     1

    # Accent ramp taken from the LiberNT logo (#0077C3) down to the navy taskbar (#091A40)
    # Order: light3, light2, light1, base, dark1, dark2, dark3, grey  (R,G,B,0 each)
    [byte[]]$palette = 0x99,0xD1,0xF2,0x00,  0x60,0xB4,0xE8,0x00,  0x2A,0x94,0xD6,0x00,  0x00,0x77,0xC3,0x00,
                       0x0A,0x4E,0x92,0x00,  0x0B,0x2F,0x66,0x00,  0x09,0x1A,0x40,0x00,  0x88,0x88,0x88,0x00
    $acc = "$Root\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
    Set-Reg $acc 'AccentPalette'   $palette 'Binary'
    Set-Reg $acc 'AccentColorMenu' (ConvertTo-DWord '0xFF924E0A')   # ABGR of #0A4E92
    Set-Reg $acc 'StartColorMenu'  (ConvertTo-DWord '0xFF662F0B')   # ABGR of #0B2F66

    $dwm = "$Root\Software\Microsoft\Windows\DWM"
    Set-Reg $dwm 'AccentColor'           (ConvertTo-DWord '0xFFC37700')  # ABGR of #0077C3
    Set-Reg $dwm 'ColorizationColor'     (ConvertTo-DWord '0xC40077C3')  # ARGB
    Set-Reg $dwm 'ColorizationAfterglow' (ConvertTo-DWord '0xC40077C3')
    Set-Reg $dwm 'ColorPrevalence'       0   # keep window title bars neutral, like LiberNT

    # Taskbar: nothing but Start + tray; Start centred unless -StartLeft
    $adv = "$Root\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-Reg $adv 'TaskbarAl'          ([int](-not $StartLeft))   # 0 = left, 1 = centre
    Set-Reg $adv 'ShowTaskViewButton' 0
    Set-Reg $adv 'ShowCopilotButton'  0
    Set-Reg $adv 'TaskbarMn'          0   # Chat / Teams
    Set-Reg "$Root\Software\Microsoft\Windows\CurrentVersion\Search" 'SearchboxTaskbarMode' 0

    if (-not $KeepPins) {
        $band = "$Root\Software\Microsoft\Windows\CurrentVersion\Explorer\Taskband"
        if (Test-Path -LiteralPath $band) { Remove-Item -LiteralPath $band -Recurse -Force }
    }

    # Desktop icons: This PC, user files (My Documents), Network, Recycle Bin
    $icons = "$Root\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    foreach ($clsid in '{20D04FE0-3AEA-1069-A2D8-08002B30309D}',  # This PC
                       '{59031a47-3f72-44a7-89c5-5595fe6b30ee}',  # User files
                       '{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}',  # Network
                       '{645FF040-5081-101B-9F08-00AA002F954E}') { # Recycle Bin
        Set-Reg $icons $clsid 0
    }
}

function Update-Desktop([string]$WallpaperPath) {
    Add-Type -Namespace LiberNT -Name Native -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@ -ErrorAction SilentlyContinue
    # SPI_SETDESKWALLPAPER = 20; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE = 3
    [void][LiberNT.Native]::SystemParametersInfo(20, 0, $WallpaperPath, 3)
    # Explorer reads taskbar settings at start-up; Windows relaunches it automatically.
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
}

# ---------------------------------------------------------------- bake into ISO

function Find-Oscdimg {
    if ($Oscdimg) { if (Test-Path $Oscdimg) { return (Resolve-Path $Oscdimg).Path } else { throw "oscdimg.exe not found at $Oscdimg" } }
    $candidates = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        (Join-Path $PSScriptRoot 'oscdimg.exe'),
        (Join-Path (Split-Path -Parent (Resolve-Path $Iso).Path) 'oscdimg.exe')
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw "oscdimg.exe not found. Copy it from your Tiny11 Builder folder next to this script, or pass -Oscdimg <path>."
}

function Invoke-Bake {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Baking into an ISO needs an Administrator PowerShell window.'
    }
    $Iso = (Resolve-Path $Iso).Path
    if (-not $OutIso) { $OutIso = Join-Path (Split-Path -Parent $Iso) (([IO.Path]::GetFileNameWithoutExtension($Iso)) + '-libernt.iso') }
    $osc = Find-Oscdimg

    $isoDir   = Join-Path $WorkDir 'iso'
    $mountDir = Join-Path $WorkDir 'mount'
    if (Test-Path $WorkDir) { throw "$WorkDir already exists. Delete it (or pass -WorkDir) and run again." }
    New-Item -ItemType Directory -Path $isoDir, $mountDir -Force | Out-Null

    # Wallpaper first, so a network problem stops us before any long step
    $stage = Join-Path $WorkDir 'stage'
    $wp = Get-Wallpaper $stage
    if ($AllWallpapers) { Get-AllWallpapers $stage }
    Copy-Item $PSCommandPath (Join-Path $stage 'libernt-look.ps1') -Force

    Write-Host '[1/5] Copying ISO contents...'
    $img = Mount-DiskImage -ImagePath $Iso -PassThru
    try {
        $drive = ($img | Get-Volume).DriveLetter
        robocopy "$($drive):\" $isoDir /E /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Copying the ISO failed (robocopy code $LASTEXITCODE)." }
    } finally { Dismount-DiskImage -ImagePath $Iso | Out-Null }
    Get-ChildItem $isoDir -Recurse -File | ForEach-Object { $_.IsReadOnly = $false }

    $wim = Join-Path $isoDir 'sources\install.wim'
    $esd = Join-Path $isoDir 'sources\install.esd'
    if (-not (Test-Path $wim)) {
        if (-not (Test-Path $esd)) { throw 'No install.wim or install.esd found in the ISO.' }
        Write-Host '[2/5] Converting install.esd to install.wim (Tiny11 ships ESD; this takes a while)...'
        foreach ($i in (Get-WindowsImage -ImagePath $esd)) {
            Export-WindowsImage -SourceImagePath $esd -SourceIndex $i.ImageIndex -DestinationImagePath $wim -CompressionType Max | Out-Null
        }
        Remove-Item $esd -Force
    } else { Write-Host '[2/5] install.wim found.' }

    foreach ($i in (Get-WindowsImage -ImagePath $wim)) {
        Write-Host "[3/5] Applying the LiberNT look to: $($i.ImageName)"
        Mount-WindowsImage -ImagePath $wim -Index $i.ImageIndex -Path $mountDir | Out-Null
        $saved = $false
        try {
            $target = Join-Path $mountDir ($InstallDir -replace '^C:\\', '')
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Copy-Item (Join-Path $stage '*') $target -Force

            & reg.exe load 'HKLM\LNT_DEFAULT' (Join-Path $mountDir 'Users\Default\NTUSER.DAT') | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not load the Default user registry hive.' }
            try {
                $root = 'Registry::HKEY_LOCAL_MACHINE\LNT_DEFAULT'
                Set-LiberNTLook -Root $root -WallpaperPath "$InstallDir\$WallpaperName"
                # Re-apply at each new user's first sign-in, after Windows sets its default theme
                $flags = '-FirstLogon'
                if ($StartLeft) { $flags += ' -StartLeft' }
                if ($KeepPins)  { $flags += ' -KeepPins' }
                Set-Reg "$root\Software\Microsoft\Windows\CurrentVersion\RunOnce" 'LiberNTLook' `
                    "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$InstallDir\libernt-look.ps1`" $flags" 'String'
            } finally {
                [GC]::Collect(); [GC]::WaitForPendingFinalizers(); Start-Sleep -Seconds 2
                & reg.exe unload 'HKLM\LNT_DEFAULT' | Out-Null
            }
            Write-Host '      Saving image...'
            Dismount-WindowsImage -Path $mountDir -Save | Out-Null
            $saved = $true
        } finally {
            if (-not $saved) { Dismount-WindowsImage -Path $mountDir -Discard -ErrorAction SilentlyContinue | Out-Null }
        }
    }

    Write-Host '[4/5] Building the new ISO...'
    $boot = "2#p0,e,b$isoDir\boot\etfsboot.com#pEF,e,b$isoDir\efi\microsoft\boot\efisys.bin"
    & $osc '-m' '-o' '-u2' '-udfver102' "-bootdata:$boot" $isoDir $OutIso
    if ($LASTEXITCODE -ne 0) { throw "oscdimg failed (code $LASTEXITCODE). The work folder was kept at $WorkDir." }

    Write-Host '[5/5] Cleaning up...'
    Remove-Item $WorkDir -Recurse -Force
    Write-Host "Done: $OutIso" -ForegroundColor Green
}

# ---------------------------------------------------------------- main

switch ($PSCmdlet.ParameterSetName) {
    'Bake' { Invoke-Bake }
    'FirstLogon' {
        # Runs once at a new user's first sign-in on an image baked by this script
        $wp = Join-Path $PSScriptRoot $WallpaperName
        Set-LiberNTLook -Root 'HKCU:' -WallpaperPath $wp
        Start-Sleep -Seconds 8   # let the first-sign-in desktop finish loading
        Update-Desktop $wp
    }
    default {
        $dir = if (Test-Path (Join-Path $InstallDir $WallpaperName)) { $InstallDir } else { Join-Path $env:USERPROFILE 'Pictures\LiberNT' }
        $wp = Get-Wallpaper $dir
        if ($AllWallpapers) { Get-AllWallpapers $dir; Write-Host "Wallpapers saved in $dir" }
        Set-LiberNTLook -Root 'HKCU:' -WallpaperPath $wp
        Update-Desktop $wp
        Write-Host 'LiberNT look applied.' -ForegroundColor Green
    }
}
