# Silience I kill you!
Set-PSReadlineOption -BellStyle None


$DefaultUser = if ($env:USERNAME) {
  "$env:USERNAME"
} else {
  "$env:USER"
}

$chocoProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path "$chocoProfile") {
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
  "DockerCompletion",
  "posh-git",
  "oh-my-posh",
  "PSReadLine",
  "cd-extras"
)

$_PSVersion = $PSVersionTable.PSVersion.Major
$_File = "$PSScriptRoot/installed/$_PSVersion.test"
if (!(Test-Path $_File)) {
  Update-Repo
  $modules | Install-Modules
  New-Item -Path $_File -ItemType File -Force | Out-Null
}

$modules | Get-EnsureModule

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

$developmentWorkspace =
if ($IsWindows) {
  @("C:\git\code", "C:\git\work")
} else {
  @("~/git/code", "~/git/work")
}

# Helper function to change directory to your development workspace
function cws { Set-Location "$($developmentWorkspace.Get(0))" }

function sln {
  Get-ChildItem -Filter "*.sln" -Recurse | Select-Object -first 1 | Invoke-Item
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
  $path = "C:\windows\system32\drivers\etc\hosts"
  if ($IsWindows) {
    $path = "C:\windows\system32\drivers\etc\hosts"
  } elseif ($IsLinux) {
    $path = "/etc/hosts"
  }
  Start-Process "code" -ArgumentList "$path"
}

function dotfile {
  $dotfile = 'https://github.com/casz/dotfiles'
  if ($IsLinux) {
    Invoke-Expression "xdg-open $dotfile"
  } else {
    Invoke-Expression "cmd.exe /C start $dotfile"
  }
}

function fork {
  param (
    [string] $repo,
    [string] $folder = (Split-Path -Leaf $repo).Replace('.git', '')
  )
  $folder = $folder -replace '[/\\-]', '.'
  hub clone $repo $folder
  Set-Location $folder
  git remote rename origin upstream
  hub fork --remote-name origin
  git fetch --all
}

function rimraf {
  param (
    [string[]] $paths
  )
  Remove-Item -Force -Recurse $paths
}

# setup cd extras
$cde.CD_PATH = @($developmentWorkspace)

# Set dir, l, ll, and ls alias to use the new Get-ChildItemColor cmdlets
Set-Alias ls Get-ChildItemColorFormatWide -Option AllScope
Set-Alias l ls -Option AllScope
Set-Alias ll Get-ChildItemColor -Option AllScope
Set-Alias dir ll -Option AllScope

# setup oh-my-posh
Set-Theme Paradox

# Docker aliases
Set-Alias dcid Get-ContainerID

Set-Alias drm Remove-StoppedContainers

Set-Alias drmi Remove-DanglingImages

Set-Alias drmv Remove-DanglingVolumes

Set-Alias dip Get-ContainerIPAddress

Set-Alias dc docker-compose

Set-Alias d docker

# Basic git alias
Set-Alias git hub

Set-Alias g git

Set-Alias open Invoke-Item

# clear variables
Remove-Variable _PSVersion, _File, modules

if ((Get-Location).Path -eq "/mnt/c/Users/$DefaultUser") {
  Set-Location ~
}

if ("$ENV:PATH" -notlike "*$ENV:HOME/bin*") {
  $ENV:PATH += [IO.Path]::PathSeparator + "$ENV:HOME/bin"
}
