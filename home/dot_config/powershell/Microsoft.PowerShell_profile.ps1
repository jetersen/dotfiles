# Silience I kill you!
Set-PSReadlineOption -BellStyle None

if ($null -eq $IsWindows -or $IsWindows -eq $true) {
  if (!$env:ChocolateyInstall) {
    $env:ChocolateyInstall = "C:\ProgramData\chocolatey"
  }
  $chocoProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
  if ([System.IO.File]::Exists("$chocoProfile")) {
    Import-Module "$chocoProfile"
  }
  $env:SESSIONDEFAULTUSER = $env:USERNAME
} else {
  $env:SESSIONDEFAULTUSER = $env:USER
}

$env:EDITOR = "code --wait"

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

function dcid { docker ps -l -q }

function dip {
  param ([string] $id)
  & docker inspect --format '{{ .NetworkSettings.Networks.nat.IPAddress }}' $id
}
function git {
  $gitExe = (Get-Command git -CommandType Application).Source
  if ($args[0] -eq 'clone') {
    $output = & $gitExe @args 2>&1 | Out-String
    Write-Host $output.TrimEnd()
    if ($LASTEXITCODE -eq 0 -and $output -match "Cloning into '(.+?)'") {
      $dirName = $Matches[1]
      if (Test-Path $dirName -PathType Container) {
        Set-Location $dirName
      }
    }
  } else {
    & $gitExe @args
  }
}

function gh {
  $ghExe = (Get-Command gh -CommandType Application).Source
  if ($args[0] -eq 'repo' -and $args[1] -eq 'clone') {
    $output = & $ghExe @args 2>&1 | Out-String
    Write-Host $output.TrimEnd()
    if ($LASTEXITCODE -eq 0 -and $output -match "Cloning into '(.+?)'") {
      $dirName = $Matches[1]
      if (Test-Path $dirName -PathType Container) {
        Set-Location $dirName
      }
    }
  } else {
    & $ghExe @args
  }
}
# END of functions

$__modules = (
  "Get-ChildItemColor",
  "posh-git",
  "cd-extras"
)

# Check marker file to see if modules have been installed for this PS version
$__markerFile = "$PSScriptRoot/.installed-ps$($PSVersionTable.PSVersion.Major)"
if (-not [System.IO.File]::Exists($__markerFile)) {
  Update-Repo
  $__modules | Install-Modules
  New-Item -Path $__markerFile -ItemType File -Force | Out-Null
}

if ($IsWindows -and [System.IO.File]::Exists("$ENV:PROGRAMFILES\gsudo\Current\gsudoModule.psd1")) {
  Import-Module "$ENV:PROGRAMFILES\gsudo\Current\gsudoModule.psd1"
}

$__modules | Get-EnsureModule
Remove-Item Function:\Get-EnsureModule, Function:\Install-Modules

Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

$developmentWorkspace =
if ($IsLinux -or $IsMacOS) {
  @("~/git/code", "~/git/work")
} else {
  @(
    "C:\git\code"
    "C:\git\work"
    "D:\git\code"
    "D:\git\work"
  )
}

# Helper function to change directory to your development workspace
function cws { Set-Location "$($developmentWorkspace.Get(0))" }

function ride {
  param (
    [string] $path = "."
  )
  $project = Get-ChildItem -Path $path -Filter "*.sln" -Recurse | Select-Object -First 1
  if (!$project) {
    $project = Get-ChildItem -Path $path -Filter "*.csproj" -Recurse | Select-Object -First 1
  }
  $target = if ($project) { $project.FullName } else { "." }
  if ($IsLinux -or $IsMacOS) {
    open $target
  } else {
    rider.cmd -ArgumentList $target
  }
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
  if ($IsLinux -or $IsMacOS) {
    sudoedit /etc/hosts
  } else {
    Start-Process "code" -ArgumentList "C:\windows\system32\drivers\etc\hosts"
  }
}

function open {
  param (
    [string] $item
  )
  if ($IsLinux) {
    Invoke-Expression "xdg-open $item"
  } elseif ($IsMacOS) {
    & /usr/bin/open $item
  } elseif ($item -and $item -imatch "https?://*") {
    Start-Process -Path "$item"
  } else {
    Invoke-Item $item
  }
}

function dotfile {
  open 'https://github.com/jetersen/dotfiles'
}

function rimraf {
  $paths = [string[]]$args

  Remove-Item -Force -Recurse $paths
}

function Invoke-GitHubAutoMerge {
  param([string] $Login)
  if ($Login) {
    $prs = [int[]](gh pr list --author $Login --json number --jq '.[].number')
  } else {
    $prs = [int[]](gh pr list --json number,author --jq '[.[] | select(.author.is_bot)] | .[].number')
  }
  $prs | Sort-Object | ForEach-Object { gh pr review $_ --approve; gh pr merge $_ --squash --auto }
}

function myip { Invoke-RestMethod -Uri 'https://api.ipify.org' }
function myip6 { Invoke-RestMethod -Uri 'https://api6.ipify.org' }

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

# Docker aliases
function dc { docker compose @args }
function dprune { docker system prune @args }

Set-Alias d docker

Set-Alias g git
Set-Alias vim nvim
Set-Alias vi nvim

if ($IsLinux -or $IsMacOS) {
  Set-Alias pip pip3
  Set-Alias python python3
}

# clear variables
Remove-Variable -Name "__*" -ErrorAction SilentlyContinue

if ((Get-Location).Path -eq "/mnt/c/Users/$DefaultUser") {
  Set-Location ~
}

if ("$ENV:PATH" -notlike "*$HOME/bin*") {
  $ENV:PATH += [IO.Path]::PathSeparator + "$HOME/bin"
}

if (Get-Command "oh-my-posh" -ErrorAction SilentlyContinue) {
  oh-my-posh init pwsh --config "$HOME/.config/oh-my-posh/jetersen.omp.json" | Invoke-Expression
}
