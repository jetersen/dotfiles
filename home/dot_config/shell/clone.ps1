function __Get-CloneDest {
  param([switch]$GitHub, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  if ($Arguments -contains '--bare' -or $Arguments -contains '--mirror') { return $null }
  $valueFlags = @('-b','--branch','-o','--origin','-c','--config','-u','--upload-pack','-j','--jobs','--depth','--reference','--reference-if-able','--template','--separate-git-dir','--filter','--revision','--server-option','--shallow-since','--shallow-exclude','--ref-format','--bundle-uri','--upstream-remote-name')
  $positionals = @()
  $skip = $false
  $endOptions = $false
  foreach ($a in $Arguments) {
    if ($skip) { $skip = $false; continue }
    if (-not $endOptions) {
      if ($a -eq '--') {
        if ($GitHub) { break }
        $endOptions = $true
        continue
      }
      if ($valueFlags -contains $a) { $skip = $true; continue }
      if ($a -like '-*') { continue }
    }
    $positionals += $a
  }
  if ($positionals.Count -ge 2) { return $positionals[1] }
  if ($positionals.Count -ge 1) {
    $name = ($positionals[0].TrimEnd('/') -split '[/\\:]')[-1]
    return ($name -replace '\.git$','')
  }
  return $null
}

function git {
  $gitExe = (Get-Command git -CommandType Application | Select-Object -First 1).Source
  if ($args[0] -eq 'clone') {
    $rest = @($args | Select-Object -Skip 1)
    $dest = __Get-CloneDest @rest
    & $gitExe @args
    if ($LASTEXITCODE -eq 0 -and $dest -and (Test-Path -LiteralPath $dest -PathType Container)) {
      Set-Location -LiteralPath $dest -ErrorAction Stop
    }
  } else {
    & $gitExe @args
  }
}

function gh {
  $ghExe = (Get-Command gh -CommandType Application | Select-Object -First 1).Source
  if ($args[0] -eq 'repo' -and $args[1] -eq 'clone') {
    $rest = @($args | Select-Object -Skip 2)
    $dest = __Get-CloneDest -GitHub @rest
    & $ghExe @args
    if ($LASTEXITCODE -eq 0 -and $dest -and (Test-Path -LiteralPath $dest -PathType Container)) {
      Set-Location -LiteralPath $dest -ErrorAction Stop
    }
  } else {
    & $ghExe @args
  }
}
