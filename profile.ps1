# Silience I kill you!
Set-PSReadlineOption -BellStyle None

$DefaultUser = "$env:USERNAME"

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
        Import-Module $moduleName
      }
    }
  }
  End {
    Write-Host "Modules loaded"
  }
}

function Install-Modules {
  $installedModules = Get-InstalledModule
  $checkRepo = $true
  if ($checkRepo) {
    Update-Repo
    $checkRepo = $false
  }
  foreach ($moduleName in $modulesNames) {
    if (!(Get-Module -Name $moduleName)) {
      if ($installedModules.Name -notcontains $moduleName) {
        Install-Module $moduleName -Scope CurrentUser -Force
      }
    }
  }
}

function Update-Modules {
  Update-Repo
  $installedModules = Get-InstalledModule
  foreach ($module in $installedModules) {
    Try {
      Write-Host "Checking $($module.name)"
      $online = Find-Module $module.name
    }
    Catch {
      Write-Warning "Module $($module.name) was not found in the PSGallery"
    }
    if ($online.version -gt $module.version) {
      Write-Host "Updating $($module.name) module"
      Update-Module "${module.name}"
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
function Get-ContainerID {(docker ps -l -q)}

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
  "posh-docker",
  "posh-git",
  "oh-my-posh",
  "PSReadLine",
  "cd-extras"
)

$modules | Get-EnsureModule

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

$developmentWorkspace = @("C:\code", "C:\work")

# Helper function to change directory to your development workspace
function cws { Set-Location "$developmentWorkspace" }

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
  if ($IsWindows) {
    $path = "C:\windows\system32\drivers\etc\hosts"
  } elseif ($IsLinux) {
    $path = "/etc/hosts"
  }
  Start-Process "code" -ArgumentList "$path" -Verb RunAs
}

# setup cd extras
$cde.CD_PATH = @("$developmentWorkspace")

# Set dir, l, ll, and ls alias to use the new Get-ChildItemColor cmdlets
Set-Alias ls Get-ChildItemColorFormatWide -Option AllScope
Set-Alias l ls -Option AllScope
Set-Alias ll Get-ChildItemColor -Option AllScope
Set-Alias dir ll -Option AllScope

# setup oh-my-posh
Set-Theme agnoster

# Docker aliases
Set-Alias dl Get-ContainerID

Set-Alias drm Remove-StoppedContainers

Set-Alias drmi Remove-DanglingImages

Set-Alias drmv Remove-DanglingVolumes

Set-Alias dip Get-ContainerIPAddress

Set-Alias dc docker-compose

Set-Alias d docker

# Basic git alias
Set-Alias g git

Set-Alias open Invoke-Item
