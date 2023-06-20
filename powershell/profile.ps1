# Silience I kill you!
Set-PSReadlineOption -BellStyle None

if (!$env:ChocolateyInstall) {
  $env:ChocolateyInstall = "C:\ProgramData\chocolatey"
}
$chocoProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if ([System.IO.File]::Exists("$chocoProfile")) {
  Import-Module "$chocoProfile"
}

# Modules should be installed on User scope
# if Modules are not installed on User scope please run as admin:
# Uninstall-Module -Name Module
function Get-EnsureModule {
  param(
    [parameter(Mandatory, ValueFromPipeline)]
    [string[]] $modulesNames
  )
  Process {
    foreach ($moduleName in $modulesNames) {
      if (!(Get-Module -Name $moduleName)) {
        try {
          Import-Module $moduleName -ErrorAction Stop
        } catch {
          Install-Module $moduleName -Scope CurrentUser -Force -AllowClobber
          Import-Module $moduleName
        }
      }
    }
  }
}

function Install-Modules {
  param(
    [parameter(Mandatory, ValueFromPipeline)]
    [string[]] $modulesNames
  )
  Begin {
    Write-Host "Installing Modules..."
  }
  Process {
    $installedModules = Get-InstalledModule
    $checkRepo = $true
    if ($checkRepo) {
      Update-Repo
      $checkRepo = $false
    }
    foreach ($moduleName in $modulesNames) {
      if (!(Get-Module -Name $moduleName)) {
        if ($installedModules.Name -notcontains $moduleName) {
          Write-Host "Installing $moduleName"
          Install-Module $moduleName -Scope CurrentUser -Force -AllowClobber
        }
      }
    }
  }
  End {
    Write-Host "Modules Installed"
  }
}

function Update-Modules {
  Update-Repo
  $installedModules = Get-InstalledModule
  foreach ($module in $installedModules) {
    Try {
      Write-Host "Checking $($module.name)"
      $online = Find-Module $module.name
    } Catch {
      Write-Warning "Module $($module.name) was not found in the PSGallery"
    }
    if ($online.version -gt $module.version) {
      Write-Host "Updating $($module.name) module"
      Update-Module -Name $module.name
    }
  }
}

function Update-Repo {
  # Ensure package mangers are installed
  $packageProviders = PackageManagement\Get-PackageProvider -ListAvailable
  $checkPowerShellGet = $packageProviders | Where-Object name -eq "PowerShellGet"
  $checkNuget = $packageProviders | Where-Object name -eq "NuGet"
  $checkPSGallery = Get-PSRepository PSGallery
  if (!$checkPSGallery -or $checkPSGallery.InstallationPolicy -ne 'Trusted') {
    Set-PSRepository PSGallery -InstallationPolicy trusted -SourceLocation "https://www.powershellgallery.com/api/v2"
  }
  if (!$checkPowerShellGet) {
    PackageManagement\Get-PackageProvider -Name PowerShellGet -Force
  }
  if (!$checkNuget) {
    PackageManagement\Get-PackageProvider -Name NuGet -Force
  }
}

# docker ps -l -q
function Get-ContainerID { (docker ps -l -q) }

#docker rm $(docker ps -a -q)
function Remove-StoppedContainers {
  foreach ($id in & docker ps -a -q) {
    & docker rm -f $id
  }
}

#docker rmi $(docker images -f "dangling=true" -q)
function Remove-DanglingImages {
  foreach ($id in & docker images -q -f 'dangling=true') {
    & docker rmi $id
  }
}

function Remove-AllImages {
  foreach ($id in & docker images -a -q) {
    & docker rmi -f $id
  }
}

#docker volume rm $(docker volume ls -qf dangling=true)
function Remove-DanglingVolumes {
  foreach ($id in & docker volume ls -q -f 'dangling=true') {
    & docker volume rm $id
  }
}

# docker inspect --format '{{ .NetworkSettings.Networks.nat.IPAddress }}' <id>
function Get-ContainerIPAddress {
  param (
    [string] $id
  )
  & docker inspect --format '{{ .NetworkSettings.Networks.nat.IPAddress }}' $id
}
# END of functions

$modules = (
  "Get-ChildItemColor",
  "posh-git",
  "cd-extras"
)

$_PSVersion = $PSVersionTable.PSVersion.Major
$_File = "$PSScriptRoot/installed/$_PSVersion.test"
if ([System.IO.File]::Exists($_File) -eq $false) {
  Update-Repo
  $modules | Install-Modules
  New-Item -Path $_File -ItemType File -Force | Out-Null
}

$modules | Get-EnsureModule

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

$developmentWorkspace =
if ($IsLinux -or $IsMacOS) {
  @("~/git/code", "~/git/work")
} else {
  @("C:\git\code", "C:\git\work")
}

# Helper function to change directory to your development workspace
function cws { Set-Location "$($developmentWorkspace.Get(0))" }

function Get-FirstProject {
  param (
    [string] $path = "."
  )
  $sln = Get-ChildItem -Path $path -Filter "*.sln" -Recurse | Select-Object -first 1
  if ($sln) {
    return $sln.FullName
  }
  $csproj = Get-ChildItem -Path $path -Filter "*.csproj" -Recurse | Select-Object -first 1
  if ($csproj) {
    return $csproj.FullName
  }
  return "."
}

function sln {
  param (
    [string] $path
  )
  Get-FirstProject "$path" | Invoke-Item
}

function ride {
  param (
    [string] $path
  )
  Rider.cmd (Get-FirstProject "$path")
}

function clean-sln {
  $cleanup = @(
    '.vs',
    'bin',
    'obj'
  )
  Get-ChildItem $cleanup -Directory -Recurse | Remove-Item -Force -Recurse
}

function hostfile {
  $path =
  if ($IsLinux -or $IsMacOS) {
    "/etc/hosts"
  } else {
    "C:\windows\system32\drivers\etc\hosts"
  }
  Start-Process "code" -ArgumentList "$path"
}

function Open-Browser {
  param (
    [string] $url
  )
  if ($IsLinux) {
    Invoke-Expression "xdg-open $url"
  } else {
    Start-Process -Path "$url"
  }
}

function open {
  param (
    [string] $item
  )
  if ($item -and $item -imatch "https?://*") {
    Open-Browser $item
  } else {
    Invoke-Item $item
  }
}

function dotfile {
  Open-Browser 'https://github.com/jetersen/dotfiles'
}

function rimraf {
  $paths = [string[]]$args

  Remove-Item -Force -Recurse $paths
}

function Update-ScreenResolution {
  $listScreens = ChangeScreenResolution.exe /l
  $regex = '(?sm)\[2\].+?Settings: (\d{4})x(\d{4})'
  $groups = ($listScreens | Out-String | Select-String -Pattern $regex).Matches.Groups
  $height = 1440
  $width = [int]$groups[1].Value
  if ($width -eq 2560) {
    $width = 3440
  } elseif ($width -eq 3440) {
    $width = 2560
  } else {
    $width = 3440
  }
  ChangeScreenResolution.exe /d=2 /w=$width /h=$height /f=100 | Out-Null
}

function Get-MyIp {
  $ip = Invoke-RestMethod -Uri 'https://ifconfig.me/ip'
  $ip
}

function Stop-Spotify {
  Get-Process -Name 'Spotify' | Stop-Process
}

function DotEnv {
  [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
  param(
    [string] $localEnvFile = "$PWD\.env"
  )

  Write-Host "Loading environment variables from $localEnvFile"

  #return if no env file
  if ([System.IO.File]::Exists($localEnvFile) -eq $false) {
    Write-Verbose "No .env file"
    return
  }

  #read the local env file
  $content = Get-Content $localEnvFile -ErrorAction Stop
  Write-Verbose "Parsed .env file"

  #load the content to environment
  foreach ($line in $content) {

    if ([string]::IsNullOrWhiteSpace($line)) {
      Write-Verbose "Skipping empty line"
      continue
    }

    #ignore comments
    if ($line.StartsWith("#")) {
      Write-Verbose "Skipping comment: $line"
      continue
    }

    #get the operator
    if ($line -like "*:=*") {
      Write-Verbose "Prefix"
      $kvp = $line -split ":=", 2
      $key = $kvp[0].Trim()
      $value = "{0};{1}" -f $kvp[1].Trim(), [System.Environment]::GetEnvironmentVariable($key)
    } elseif ($line -like "*=:*") {
      Write-Verbose "Suffix"
      $kvp = $line -split "=:", 2
      $key = $kvp[0].Trim()
      $value = "{1};{0}" -f $kvp[1].Trim(), [System.Environment]::GetEnvironmentVariable($key)
    } else {
      Write-Verbose "Assign"
      $kvp = $line -split "=", 2
      $key = $kvp[0].Trim()
      $value = $kvp[1].Trim()
    }

    Write-Verbose "$key=$value"

    if ($PSCmdlet.ShouldProcess("environment variable $key", "set value $value")) {
      [Environment]::SetEnvironmentVariable($key, $value, "Process") | Out-Null
    }
  }
}

# setup cd extras
$cde.CD_PATH = @($developmentWorkspace)

# Set dir, l, ll, and ls alias to use the new Get-ChildItemColor cmdlets
Set-Alias ls Get-ChildItemColorFormatWide -Option AllScope
Set-Alias l ls -Option AllScope
Set-Alias ll Get-ChildItemColor -Option AllScope
Set-Alias dir ll -Option AllScope

# setup oh-my-posh
if ($ENV:WSL_DISTRO_NAME) {
  $env:SESSIONDEFAULTUSER = $env:USER
  Invoke-Expression (oh-my-posh --init --shell pwsh --config "$ENV:HOME/.jetersen.omp.json")
} else {
  $env:SESSIONDEFAULTUSER = $env:USERNAME
  Invoke-Expression (oh-my-posh --init --shell pwsh --config "$ENV:USERPROFILE/.jetersen.omp.json")
}



# Docker aliases
Set-Alias dcid Get-ContainerID

Set-Alias drm Remove-StoppedContainers

Set-Alias drmi Remove-DanglingImages

Set-Alias drmv Remove-DanglingVolumes

Set-Alias dip Get-ContainerIPAddress

Set-Alias dc docker-compose

Set-Alias d docker

Set-Alias g git

# clear variables
Remove-Variable _PSVersion, _File, modules

if ((Get-Location).Path -eq "/mnt/c/Users/$DefaultUser") {
  Set-Location ~
}

if ("$ENV:PATH" -notlike "*$ENV:HOME/.bin*") {
  $ENV:PATH += [IO.Path]::PathSeparator + "$ENV:HOME/.bin"
}

# Chocolatey profile
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}
