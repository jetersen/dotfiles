#Requires -Version 7

# =============================================================================
# User-level Configuration (no elevation required)
# =============================================================================

#--- Keyboard languages ---
Set-WinUserLanguageList -LanguageList en-US, da -Force

#--- Explorer settings ---
# Show hidden files, protected OS files, file extensions
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value 1
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowSuperHidden' -Value 1
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0
# Expand explorer to actual folder
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'NavPaneExpandToCurrentFolder' -Value 1
# Open PC to This PC, not quick access
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'LaunchTo' -Value 1
# Taskbar where window is open for multi-monitor
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'MMTaskbarMode' -Value 2
# Disable Bing search suggestions
New-Item -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Force | Out-Null
Set-ItemProperty -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Value 1
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0

# Mixed Reality Portal
$Holo = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Holographic"
if (Test-Path $Holo) {
  Set-ItemProperty $Holo FirstRunSucceeded -Value 0
}

# Disable live tiles
$Live = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications"
if (!(Test-Path $Live)) { New-Item $Live }
Set-ItemProperty $Live NoTileApplicationNotification -Value 1

# Disable People icon on Taskbar
$People = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People'
if (Test-Path $People) {
  Set-ItemProperty $People -Name PeopleBand -Value 0
}

# Content Delivery Manager
$registryOEM = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
if (!(Test-Path $registryOEM)) { New-Item $registryOEM }
Set-ItemProperty $registryOEM ContentDeliveryAllowed -Value 0
Set-ItemProperty $registryOEM OemPreInstalledAppsEnabled -Value 0
Set-ItemProperty $registryOEM PreInstalledAppsEnabled -Value 0
Set-ItemProperty $registryOEM PreInstalledAppsEverEnabled -Value 0
Set-ItemProperty $registryOEM SilentInstalledAppsEnabled -Value 0
Set-ItemProperty $registryOEM SystemPaneSuggestionsEnabled -Value 0

# =============================================================================
# Remove Default Apps
# =============================================================================

if ((Get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -ErrorAction SilentlyContinue).DisableWindowsConsumerFeatures -ne 1) {
  Write-Host "Uninstalling unnecessary default Windows apps..." -ForegroundColor Yellow

  function removeApp {
    param([string]$appName)
    Write-Output "Trying to remove $appName"
    Get-AppxPackage $appName -AllUsers | Remove-AppxPackage
    Get-AppXProvisionedPackage -Online | Where-Object DisplayName -like $appName | Remove-AppxProvisionedPackage -Online
  }

  $applicationList = @(
    "Microsoft.BingFinance"
    "Microsoft.3DBuilder"
    "Microsoft.BingNews"
    "Microsoft.BingSports"
    "Microsoft.BingWeather"
    "Microsoft.CommsPhone"
    "Microsoft.Getstarted"
    "Microsoft.WindowsMaps"
    "*MarchofEmpires*"
    "Microsoft.StorePurchaseApp"
    "Microsoft.Office.Todo.List"
    "Microsoft.GetHelp"
    "Microsoft.Microsoft3DViewer"
    "Microsoft.Messaging"
    "*Minecraft*"
    "Microsoft.MicrosoftOfficeHub"
    "Microsoft.OneConnect"
    "Microsoft.WindowsPhone"
    "Microsoft.WindowsSoundRecorder"
    "*Solitaire*"
    "Microsoft.WindowsAlarms"
    "Microsoft.MicrosoftStickyNotes"
    "Microsoft.Office.OneNote"
    "Microsoft.Office.Sway"
    "Microsoft.XboxApp"
    "Microsoft.Xbox.TCUI"
    "Microsoft.XboxGameOverlay"
    "Microsoft.XboxIdentityProvider"
    "Microsoft.XboxSpeechToTextOverlay"
    "Microsoft.XboxGameCallableUI"
    "Microsoft.XboxGamingOverlay"
    "Microsoft.ZuneMusic"
    "Microsoft.ZuneVideo"
    "Microsoft.NetworkSpeedTest"
    "Microsoft.SkypeApp"
    "Microsoft.FreshPaint"
    "Microsoft.Print3D"
    "Microsoft.People"
    "*Autodesk*"
    "*BubbleWitch*"
    "king.com*"
    "G5*"
    "*Facebook*"
    "*Keeper*"
    "*Wunderlist*"
    "*Flipboard*"
    "*Netflix*"
    "*CandyCrush*"
    "*PandoraMediaInc*"
    "*Twitter*"
    "*Plex*"
    "*Dolby*"
    "*Speed Test*"
    "*Royal Revolt*"
    "*.Duolingo-LearnLanguagesforFree"
    "*.EclipseManager"
    "ActiproSoftwareLLC.562882FEEB491" # Code Writer
    "*.AdobePhotoshopExpress"
  )

  foreach ($app in $applicationList) {
    removeApp $app
  }
}

# =============================================================================
# Elevated Configuration (single gsudo block)
# =============================================================================

gsudo {
  #--- Enable developer mode ---
  Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1

  #--- Enable TLS 1.2 on 64 bit .Net Framework ---
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v2.0.50727' -Name 'SchUseStrongCrypto' -Value 1
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value 1
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v2.0.50727' -Name 'SystemDefaultTlsVersions' -Value 1
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NetFramework\v4.0.30319' -Name 'SystemDefaultTlsVersions' -Value 1

  #--- Enable TLS 1.2 on 32 bit .Net Framework ---
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727' -Name 'SchUseStrongCrypto' -Value 1
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SchUseStrongCrypto' -Value 1
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v2.0.50727' -Name 'SystemDefaultTlsVersions' -Value 1
  Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\.NetFramework\v4.0.30319' -Name 'SystemDefaultTlsVersions' -Value 1

  #--- SSH agent ---
  Set-Service ssh-agent -StartupType Automatic

  #--- Windows Features ---
  $features = @(
    'Microsoft-Windows-Subsystem-Linux',
    'VirtualMachinePlatform',
    'Containers'
  )
  Enable-WindowsOptionalFeature -FeatureName $features -Online -All -NoRestart | Out-Null

  #--- Disable Windows Feedback Experience ---
  $Advertising = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
  if (Test-Path $Advertising) {
    Set-ItemProperty $Advertising Enabled -Value 0
  }

  #--- Stop Cortana from being used in Windows Search ---
  $Search = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
  if (Test-Path $Search) {
    Set-ItemProperty $Search AllowCortana -Value 0
  }

  #--- Disable Web Search in Start Menu ---
  $WebSearch = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
  if (!(Test-Path $WebSearch)) {
    New-Item $WebSearch
  }
  Set-ItemProperty $WebSearch DisableWebSearch -Value 1

  #--- Disable Wi-Fi Sense ---
  $WifiSense1 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting"
  $WifiSense2 = "HKLM:\SOFTWARE\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots"
  $WifiSense3 = "HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config"
  if (!(Test-Path $WifiSense1)) { New-Item $WifiSense1 }
  Set-ItemProperty $WifiSense1 Value -Value 0
  if (!(Test-Path $WifiSense2)) { New-Item $WifiSense2 }
  Set-ItemProperty $WifiSense2 Value -Value 0
  Set-ItemProperty $WifiSense3 AutoConnectAllowedOEM -Value 0

  #--- Disable Location Tracking ---
  $SensorState = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"
  $LocationConfig = "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration"
  if (!(Test-Path $SensorState)) { New-Item $SensorState }
  Set-ItemProperty $SensorState SensorPermissionState -Value 0
  if (!(Test-Path $LocationConfig)) { New-Item $LocationConfig }
  Set-ItemProperty $LocationConfig Status -Value 0

  #--- Disable unnecessary scheduled tasks ---
  $tasksToDisable = @("XblGameSaveTaskLogon", "XblGameSaveTask", "Consolidator", "UsbCeip", "DmClient", "DmClientOnScenarioDownload")
  Get-ScheduledTask | Where-Object { $_.TaskName -in $tasksToDisable } | Disable-ScheduledTask

  #--- Prevent bloatware from returning ---
  $registryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
  if (!(Test-Path $registryPath)) { New-Item $registryPath }
  Set-ItemProperty $registryPath DisableWindowsConsumerFeatures -Value 1
}

# =============================================================================
# Install Fonts
# =============================================================================

$nerdFontsFolder = "${ENV:TEMP}\nerdfonts"
if (![System.IO.Directory]::Exists($nerdFontsFolder)) {
  New-Item -Path $nerdFontsFolder -ItemType Directory | Out-Null
  $releases = Invoke-RestMethod 'https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest'
  $latestRelease = $releases.assets | Where-Object { $_.browser_download_url.EndsWith('JetBrainsMono.zip') } | Select-Object -First 1 -ExpandProperty browser_download_url
  $zipFile = "${nerdFontsFolder}\nerdfonts.zip"
  curl.exe -sSfL -o $zipFile $latestRelease
  Expand-Archive -Path $zipFile -DestinationPath $nerdFontsFolder
}

$systemFonts = @(Get-ChildItem "${ENV:WINDIR}\Fonts" | Where-Object { !$_.PSIsContainer } | Select-Object -ExpandProperty BaseName)
$userFonts = @(Get-ChildItem "${ENV:LOCALAPPDATA}\Microsoft\Windows\Fonts" -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer } | Select-Object -ExpandProperty BaseName)
$installedFonts = -join ($systemFonts + $userFonts)
$jetbrainsMonoNFs = @(Get-ChildItem "$nerdFontsFolder\JetBrainsMonoNerdFont*.ttf" -Recurse | Where-Object { $installedFonts -inotlike "*$($_.BaseName)*" })

$jetbrainsFolder = "${ENV:TEMP}\jetbrainsmono"
if (![System.IO.Directory]::Exists($jetbrainsFolder)) {
  New-Item -Path $jetbrainsFolder -ItemType Directory | Out-Null
  $releases = Invoke-RestMethod 'https://api.github.com/repos/JetBrains/JetBrainsMono/releases/latest'
  $latestRelease = $releases.assets | Where-Object { $_.browser_download_url.EndsWith('zip') } | Select-Object -First 1 -ExpandProperty browser_download_url
  $zipFile = "${jetbrainsFolder}\jetbrainsmono.zip"
  curl.exe -sSfL -o $zipFile $latestRelease
  Expand-Archive -Path $zipFile -DestinationPath $jetbrainsFolder
}

$jetbrainsMonos = @(Get-ChildItem "${jetbrainsFolder}\fonts\ttf\JetBrainsMono-*.ttf" -Recurse | Where-Object { $installedFonts -inotlike "*$($_.BaseName)*" })

$fontFiles = $jetbrainsMonoNFs + $jetbrainsMonos

if ($fontFiles) {
  $installDir = "./installPlease"
  $installDirItem = New-Item $installDir -ItemType Directory -Force
  $fontFiles | Copy-Item -Force -Destination $installDirItem
  $shellApp = New-Object -ComObject shell.application
  $installingFonts = $shellApp.NameSpace("$($installDirItem.FullName)")
  $fonts = $shellApp.NameSpace(0x14)
  $fonts.CopyHere($installingFonts.Items())
  if ([System.IO.Directory]::Exists($installDir)) {
    Remove-Item $installDir -Recurse -Force
  }
}

Remove-Item $nerdFontsFolder -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $jetbrainsFolder -Recurse -Force -ErrorAction SilentlyContinue

# =============================================================================
# Create Directories
# =============================================================================

@("C:\git\code", "C:\git\work") | ForEach-Object {
  if (!(Test-Path $_)) { New-Item $_ -ItemType Directory }
}
