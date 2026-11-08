# Majula theme for Windows: the look of the Arch desktop, from the same files.
# Started by "1 - Majula theme.cmd" in the kit that windows/copy-to-windows puts on the
# Windows desktop. Only uses settings Windows itself offers; safe to run again.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$files = Join-Path $PSScriptRoot 'files'
$failed = @()

function Step([string]$title, [scriptblock]$body) {
    Write-Host "==> $title" -ForegroundColor Yellow
    try { & $body } catch {
        Write-Host "    failed: $($_.Exception.Message)" -ForegroundColor Red
        $script:failed += $title
    }
}

function Set-Reg([string]$path, [string]$name, $value, [string]$type = 'DWord') {
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}

# JSON with comments (VS Code, Windows Terminal) -> object. Drops // comment lines and
# trailing commas, which Windows PowerShell's ConvertFrom-Json does not accept.
function Read-Jsonc([string]$path) {
    if (-not (Test-Path $path)) { return New-Object psobject }
    $text = [IO.File]::ReadAllText($path)
    $text = ($text -split "`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
    $text = [regex]::Replace($text, ',(\s*[}\]])', '$1')
    if (-not $text.Trim()) { return New-Object psobject }
    return $text | ConvertFrom-Json
}

function Write-Json([string]$path, $object) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $json = $object | ConvertTo-Json -Depth 32
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding $false))
}

function Set-Field($object, [string]$name, $value) {
    $object | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
}

Add-Type -Namespace Majula -Name Native -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResource(string file);
[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
'@

$wall = Join-Path $env:WINDIR 'Web\Wallpaper\Majula\wallpaper.png'
$cursor = '%SystemRoot%\Cursors\Drangleic.cur'
# Only the arrow is the game's, like on Linux; the other pointers stay the Windows ones.
$aero = '%SystemRoot%\cursors\'
$cursors = [ordered]@{
    Arrow = $cursor; Help = "${aero}aero_helpsel.cur"; AppStarting = "${aero}aero_working.ani"
    Wait = "${aero}aero_busy.ani"; Crosshair = ''; IBeam = ''; NWPen = "${aero}aero_pen.cur"
    No = "${aero}aero_unavail.cur"; SizeNS = "${aero}aero_ns.cur"; SizeWE = "${aero}aero_ew.cur"
    SizeNWSE = "${aero}aero_nwse.cur"; SizeNESW = "${aero}aero_nesw.cur"; SizeAll = "${aero}aero_move.cur"
    UpArrow = "${aero}aero_up.cur"; Hand = "${aero}aero_link.cur"; Pin = "${aero}aero_pin.cur"
    Person = "${aero}aero_person.cur"
}

Step 'Fonts: Drangleic (the game font) and JetBrainsMono Nerd Font' {
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($f in Get-ChildItem (Join-Path $files 'fonts') -File) {
        $dest = Join-Path $env:WINDIR "Fonts\$($f.Name)"
        if (-not (Test-Path $dest) -or (Get-FileHash $dest).Hash -ne (Get-FileHash $f.FullName).Hash) {
            Copy-Item $f.FullName $dest -Force
        }
        $kind = if ($f.Extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
        Set-Reg $key "$($f.BaseName) ($kind)" $f.Name 'String'
        [void][Majula.Native]::AddFontResource($dest)
        Write-Host "    $($f.Name)"
    }
    $r = [UIntPtr]::Zero
    [void][Majula.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1D, [UIntPtr]::Zero, $null, 2, 2000, [ref]$r)  # WM_FONTCHANGE
}

Step 'Cursor: the Dark Souls II menu pointer' {
    Copy-Item (Join-Path $files 'Drangleic.cur') ([Environment]::ExpandEnvironmentVariables($cursor)) -Force
    # Also listed as the "Majula" scheme in Mouse properties > Pointers.
    Set-Reg 'HKCU:\Control Panel\Cursors\Schemes' 'Majula' (@($cursors.Values) -join ',') 'ExpandString'
}

Step 'Lock screen: Majula, without Spotlight pictures or tips' {
    New-Item -ItemType Directory -Force (Split-Path $wall) | Out-Null
    Copy-Item (Join-Path $files 'wallpaper.png') $wall -Force
    $csp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP'
    Set-Reg $csp 'LockScreenImagePath' $wall 'String'
    Set-Reg $csp 'LockScreenImageUrl' $wall 'String'
    Set-Reg $csp 'LockScreenImageStatus' 1
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($v in 'RotatingLockScreenEnabled', 'RotatingLockScreenOverlayEnabled', 'SubscribedContent-338387Enabled') {
        Set-Reg $cdm $v 0
    }
}

Step 'Theme "Majula": dark mode, gold accent, wallpaper and cursor' {
    Set-Reg 'HKCU:\Control Panel\Desktop' 'JPEGImportQuality' 100   # keep the wallpaper sharp
    $lines = @(
        '[Theme]', 'DisplayName=Majula', '',
        '[Control Panel\Desktop]', "Wallpaper=$wall", 'TileWallpaper=0', 'WallpaperStyle=10', 'Pattern=', '',
        '[VisualStyles]', 'Path=%ResourceDir%\Themes\Aero\Aero.msstyles', 'ColorStyle=NormalColor',
        'Size=NormalSize', 'AutoColorization=0', 'ColorizationColor=0XC4D1A35C', 'SystemMode=Dark',
        'AppMode=Dark', 'VisualStyleVersion=10', '',
        '[Control Panel\Cursors]'
    )
    foreach ($k in $cursors.Keys) { $lines += "$k=$($cursors[$k])" }
    $lines += 'DefaultValue=Majula', '', '[MasterThemeSelector]', 'MTSM=RJSPBS'
    $theme = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Themes\Majula.theme'
    New-Item -ItemType Directory -Force (Split-Path $theme) | Out-Null
    Set-Content -Path $theme -Value $lines -Encoding Unicode
    # Opening a .theme applies it (and opens Settings, closed again here).
    Start-Process $theme
    Start-Sleep -Seconds 6
    Get-Process SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host '    Settings > Personalization > Themes now lists "Majula"'
}

Step 'Windows Terminal: Majula colors and JetBrainsMono Nerd Font, like kitty' {
    $path = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if ((Test-Path $path) -and -not (Test-Path "$path.majula-backup")) { Copy-Item $path "$path.majula-backup" }
    $s = Read-Jsonc $path
    $scheme = [pscustomobject][ordered]@{
        name = 'Majula'; background = '#0E1114'; foreground = '#DDD6C6'; cursorColor = '#E0783E'
        selectionBackground = '#D1A35C'
        black = '#20272C'; red = '#C06452'; green = '#87996D'; yellow = '#D1A35C'
        blue = '#7899A2'; purple = '#A37F8E'; cyan = '#6F9E94'; white = '#DDD6C6'
        brightBlack = '#465056'; brightRed = '#D47A66'; brightGreen = '#A3B386'; brightYellow = '#E3BB7A'
        brightBlue = '#94B3BB'; brightPurple = '#BD9AA8'; brightCyan = '#8DB8AE'; brightWhite = '#F0EADC'
    }
    Set-Field $s 'schemes' (@(@($s.schemes) | Where-Object { $_ -and $_.name -ne 'Majula' }) + $scheme)
    # "profiles" is either a list (old format) or { defaults, list }.
    if ($s.profiles -is [array]) { Set-Field $s 'profiles' ([pscustomobject]@{ list = $s.profiles }) }
    if (-not $s.profiles) { Set-Field $s 'profiles' (New-Object psobject) }
    if (-not $s.profiles.defaults) { Set-Field $s.profiles 'defaults' (New-Object psobject) }
    $d = $s.profiles.defaults
    Set-Field $d 'colorScheme' 'Majula'
    Set-Field $d 'font' ([pscustomobject]@{ face = 'JetBrainsMono Nerd Font'; size = 10.5 })
    Set-Field $d 'opacity' 84
    Set-Field $d 'useAcrylic' $false
    Set-Field $d 'cursorShape' 'bar'
    Set-Field $d 'padding' '10'
    Write-Json $path $s
}

Step 'VS Code: Majula theme and the same settings as on Arch' {
    $code = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
              "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $code) {
        Write-Host '    VS Code is not installed; install it and run this again'
        return
    }
    & $code --install-extension (Join-Path $files 'majula-theme.vsix') --force | Out-Null
    if ($LASTEXITCODE) { throw "code --install-extension exited with $LASTEXITCODE" }
    # Your own settings stay; the ones from Arch are added on top.
    $path = Join-Path $env:APPDATA 'Code\User\settings.json'
    if ((Test-Path $path) -and -not (Test-Path "$path.majula-backup")) { Copy-Item $path "$path.majula-backup" }
    try { $s = Read-Jsonc $path } catch { $s = New-Object psobject }
    $ours = Read-Jsonc (Join-Path $files 'vscode-settings.json')
    foreach ($p in $ours.PSObject.Properties) { Set-Field $s $p.Name $p.Value }
    Write-Json $path $s
}

Write-Host ''
if ($failed) {
    Write-Host "Done, but these steps failed: $($failed -join '; ')" -ForegroundColor Red
} else {
    Write-Host 'Done. Lock the screen (Win+L) to see the new lock screen.' -ForegroundColor Green
}
