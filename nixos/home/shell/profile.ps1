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
function __Get-CloneDest {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  $valueFlags = @('-b','--branch','-o','--origin','-c','--config','-u','--upload-pack','-j','--jobs','--depth','--reference','--reference-if-able','--template','--separate-git-dir','--filter','--revision','--server-option','--shallow-since','--shallow-exclude','--ref-format','--bundle-uri','--upstream-remote-name')
  $positionals = @()
  $skip = $false
  foreach ($a in $Arguments) {
    if ($a -eq '--') { break }
    if ($skip) { $skip = $false; continue }
    if ($valueFlags -contains $a) { $skip = $true; continue }
    if ($a -like '-*') { continue }
    $positionals += $a
  }
  if ($positionals.Count -ge 2) { return $positionals[1] }
  if ($positionals.Count -ge 1) {
    $name = Split-Path -Leaf $positionals[0]
    return ($name -replace '\.git$','')
  }
  return $null
}

function __Write-GitRemote {
  $gitExe = (Get-Command git -CommandType Application).Source
  $url = (& $gitExe remote get-url origin 2>$null)
  if ($url) {
    Set-Content -Path .git-remote -Value $url -Encoding utf8
  }
}

function git {
  $gitExe = (Get-Command git -CommandType Application).Source
  if ($args[0] -eq 'clone') {
    $rest = @($args | Select-Object -Skip 1)
    $dest = __Get-CloneDest @rest
    & $gitExe @args
    if ($LASTEXITCODE -eq 0 -and $dest -and (Test-Path $dest -PathType Container)) {
      Set-Location $dest
      __Write-GitRemote
    }
  } else {
    & $gitExe @args
  }
}

function gh {
  $ghExe = (Get-Command gh -CommandType Application).Source
  if ($args[0] -eq 'repo' -and $args[1] -eq 'clone') {
    $rest = @($args | Select-Object -Skip 2)
    $dest = __Get-CloneDest @rest
    & $ghExe @args
    if ($LASTEXITCODE -eq 0 -and $dest -and (Test-Path $dest -PathType Container)) {
      Set-Location $dest
      __Write-GitRemote
    }
  } else {
    & $ghExe @args
  }
}
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
