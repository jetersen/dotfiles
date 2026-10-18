Import-Module posh-git, cd-extras, Get-ChildItemColor
Set-PSReadLineOption -BellStyle None
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
$developmentWorkspace = @("$HOME/git")
$cde.CD_PATH = $developmentWorkspace

function dcid { docker ps -l -q }

function dip {
  param ([string] $id)
  & docker inspect --format '{{range .NetworkSettings.Networks}}{{println .IPAddress}}{{end}}' $id
}
. "$HOME/.config/shell/clone.ps1"

function cws { Set-Location "$($developmentWorkspace.Get(0))" }

function ride {
  param (
    [string] $path = "."
  )
  if (Test-Path -LiteralPath $path -PathType Leaf) {
    $project = Get-Item -LiteralPath $path
  } else {
    $project = $null
    foreach ($extension in @("*.slnx", "*.slnf", "*.sln", "*.csproj")) {
      $project = Get-ChildItem -Path $path -Filter $extension -File -Recurse -Depth 3 | Select-Object -First 1
      if ($project) { break }
    }
  }
  $target = if ($project) { $project.FullName } else { $path }
  Start-Process -FilePath rider -ArgumentList ('"' + $target.Replace('"', '\"') + '"')
}

function clean-sln {
  & fd -HI -t d '^(\.vs|bin|obj)$' -x rm -rf
}

function hostfile { & sudoedit /etc/hosts }

function open {
  param([string] $item)
  & xdg-open $item
}

function dotfile { open 'https://forgejo.jetersen.dev/jetersen/dotfiles' }

function rimraf {
  $paths = [string[]]$args

  Remove-Item -Force -Recurse $paths
}

function Invoke-GitHubAutoMerge {
  param([string] $Login)
  $fields = 'number,autoMergeRequest,reviewDecision'
  if ($Login) {
    $prs = (gh pr list --author $Login --json $fields) | ConvertFrom-Json
  } else {
    $prs = (gh pr list --json "$fields,author" --jq '[.[] | select(.author.is_bot)]') | ConvertFrom-Json
  }
  $myLogin = (gh api user --jq '.login')
  foreach ($pr in $prs | Sort-Object number) {
    if ($pr.reviewDecision -ne 'APPROVED') {
      $approved = (gh api "repos/{owner}/{repo}/pulls/$($pr.number)/reviews" --jq "[.[] | select(.user.login == `"$myLogin`" and .state == `"APPROVED`")] | length")
      if ($approved -eq 0) { gh pr review $pr.number --approve }
    }
    if (-not $pr.autoMergeRequest) { gh pr merge $pr.number --rebase --auto }
  }
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
      $value = ("{0}" + [IO.Path]::PathSeparator + "{1}") -f $kvp[1].Trim(), [System.Environment]::GetEnvironmentVariable($key)
    } elseif ($line -like "*=:*") {
      Write-Verbose "Suffix"
      $kvp = $line -split "=:", 2
      $key = $kvp[0].Trim()
      $value = ("{1}" + [IO.Path]::PathSeparator + "{0}") -f $kvp[1].Trim(), [System.Environment]::GetEnvironmentVariable($key)
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

Set-Alias ls Get-ChildItemColorFormatWide -Option AllScope
Set-Alias l ls -Option AllScope
Set-Alias ll Get-ChildItemColor -Option AllScope
Set-Alias dir ll -Option AllScope
Set-Alias d docker
Set-Alias g git
Set-Alias vim nvim
Set-Alias vi nvim
Set-Alias pip pip3
Set-Alias python python3
function dc { docker compose @args }
function dprune { docker system prune @args }
function cc { claude --dangerously-skip-permissions @args }
function cx { codex --dangerously-bypass-approvals-and-sandbox @args }
function github-auto-merge { Invoke-GitHubAutoMerge @args }
