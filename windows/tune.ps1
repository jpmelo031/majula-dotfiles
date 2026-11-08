# Performance and a clean Windows: dual boot fixes, the fastest power plan, no animations,
# no ads or suggestions, less telemetry and the usual preinstalled extras removed.
# Started by "2 - Performance and cleanup.cmd" in the kit that windows/copy-to-windows puts
# on the Windows desktop. Only uses settings Windows itself offers; safe to run again.
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
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

function Run([string]$exe) {
    & $exe @args
    if ($LASTEXITCODE -notin 0, 3010) { throw "$exe $args exited with $LASTEXITCODE" }   # 3010: restart needed
}

Add-Type -Namespace Majula -Name Native -MemberDefinition @'
[DllImport("user32.dll")]
public static extern bool SystemParametersInfo(uint action, uint uiParam, IntPtr pvParam, uint flags);
[DllImport("user32.dll")]
public static extern bool SystemParametersInfo(uint action, uint uiParam, int[] pvParam, uint flags);
'@

$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

Step 'Dual boot with Arch: clock in UTC, no Fast Startup or hibernation' {
    # Linux keeps the hardware clock in UTC; without this the time is off by 3 hours here.
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' 'RealTimeIsUniversal' 1
    # Fast Startup leaves the Windows partition half-closed, so Linux can't safely touch it.
    Run powercfg /hibernate off
}

Step 'Power: Ultimate Performance plan' {
    $plan = 'd2f7b42a-1587-4e28-ad4e-619f21780644'   # this script's copy of Ultimate Performance
    if ((powercfg /list | Out-String) -notmatch $plan) {
        cmd /c "powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $plan >nul 2>&1"
        if ((powercfg /list | Out-String) -notmatch $plan) {
            $plan = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
            Write-Host '    Ultimate Performance is not offered here; using High performance'
        }
    }
    Run powercfg /setactive $plan
    # Like on Arch: the screen goes off after 15 minutes; it never sleeps on its own when plugged in.
    Run powercfg /change monitor-timeout-ac 15
    Run powercfg /change monitor-timeout-dc 10
    Run powercfg /change standby-timeout-ac 0
    Run powercfg /change standby-timeout-dc 30
}

Step 'Visual effects: no animations or transparency (shadows and smooth fonts stay)' {
    $update = 3   # save to the profile and tell running apps
    # Animation effects, menus, combo boxes, smooth list scrolling, selection fade, tooltips.
    foreach ($a in 0x1043, 0x1003, 0x1005, 0x1007, 0x1015, 0x1017) {
        [void][Majula.Native]::SystemParametersInfo($a, 0, [IntPtr]::Zero, $update)
    }
    [void][Majula.Native]::SystemParametersInfo(0x0049, 8, [int[]](8, 0), $update)   # minimize/maximize
    Set-Reg $adv 'TaskbarAnimations' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
}

Step 'Games: Game Mode on, background recording off' {
    Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
}

Step 'No ads, tips, suggested apps or web results in Start' {
    foreach ($v in 'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OemPreInstalledAppsEnabled',
                   'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled',
                   'SoftLandingEnabled', 'SystemPaneSuggestionsEnabled', 'SubscribedContentEnabled',
                   'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
                   'SubscribedContent-353698Enabled') {
        Set-Reg $cdm $v 0
    }
    Set-Reg $adv 'Start_IrisRecommendations' 0
    Set-Reg $adv 'Start_AccountNotifications' 0
    Set-Reg $adv 'ShowSyncProviderNotifications' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 0
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
}

Step 'Privacy: no advertising ID, tailored experiences, feedback prompts or telemetry service' {
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1
    Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    # Only the required diagnostic data (the same switch as in Settings > Privacy).
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 1
    Stop-Service DiagTrack -Force -ErrorAction SilentlyContinue
    Set-Service DiagTrack -StartupType Disabled
    # Windows Update downloads only from Microsoft, not to and from other PCs.
    Set-Reg 'Registry::HKEY_USERS\S-1-5-20\Software\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Settings' 'DownloadMode' 0
}

Step 'Taskbar and Explorer: no Widgets or Task View, search as an icon, file extensions shown' {
    Set-Reg $adv 'HideFileExt' 0
    Set-Reg $adv 'LaunchTo' 1   # Explorer opens on This PC
    Set-Reg $adv 'ShowTaskViewButton' 0
    # Some Windows builds protect this one.
    try { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1 }
    catch { Write-Host '    search icon: Windows blocks this setting here; pick it in Settings > Personalization > Taskbar' -ForegroundColor DarkYellow }
    # Windows blocks scripts from writing the Widgets policy, even as admin ("unauthorized
    # operation", from the UCPD driver), and LTSC has no Widgets at all. Only try it when
    # Widgets is installed, and never let it stop the rest of this step.
    if (Get-AppxPackage -AllUsers -Name 'MicrosoftWindows.Client.WebExperience') {
        try { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 }
        catch { Write-Host '    Widgets: Windows blocks this setting for scripts; turn Widgets off in Settings > Personalization > Taskbar' -ForegroundColor DarkYellow }
    }
}

Step 'Removing preinstalled extras (only the ones that are there)' {
    # Kept: Store, Edge, OneDrive, Xbox (games need it), Photos, Media Player, Phone Link,
    # Calculator, Notepad, Paint, Terminal, Snipping Tool.
    $apps = 'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GetHelp',
            'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
            'Microsoft.People', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub',
            'Microsoft.WindowsMaps', 'Microsoft.ZuneVideo', 'Microsoft.549981C3F5F10', 'Microsoft.Copilot',
            'Microsoft.Windows.DevHome', 'Microsoft.OutlookForWindows', 'Microsoft.SkypeApp', 'MSTeams',
            'MicrosoftTeams', 'MicrosoftCorporationII.MicrosoftFamily', '7EE7776C.LinkedInforWindows',
            '*SpotifyMusic*', '*Disney*', '*TikTok*', '*Instagram*', '*Facebook*', '*CandyCrush*',
            '*PrimeVideo*', '*Netflix*'
    $provisioned = @(Get-AppxProvisionedPackage -Online)   # for new user accounts
    $found = 0
    foreach ($name in $apps) {
        foreach ($p in Get-AppxPackage -AllUsers -Name $name) {
            $found++
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers
                Write-Host "    removed $($p.Name)"
            } catch { Write-Host "    could not remove $($p.Name): $($_.Exception.Message)" -ForegroundColor Red }
        }
        foreach ($p in $provisioned | Where-Object DisplayName -like $name) {
            try { Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $p.PackageName | Out-Null } catch {}
        }
    }
    if (-not $found) { Write-Host '    nothing to remove' }
}

Step 'Cleaning temporary files and old update files (takes a few minutes)' {
    # Only what is older than a day: programs that are running keep their working files here,
    # and deleting those from under them breaks them.
    $cutoff = (Get-Date).AddDays(-1)
    foreach ($dir in $env:TEMP, (Join-Path $env:WINDIR 'Temp')) {
        Get-ChildItem $dir -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Run Dism.exe /Online /Cleanup-Image /StartComponentCleanup /NoRestart
}

# The taskbar and Explorer pick up their settings when Explorer restarts (it comes back by itself).
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($failed) {
    Write-Host "Done, but these steps failed: $($failed -join '; ')" -ForegroundColor Red
} else {
    Write-Host 'Done. Restart Windows once to apply everything.' -ForegroundColor Green
}
