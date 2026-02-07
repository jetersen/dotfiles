$ErrorActionPreference = 'Stop'

if ($null -eq $IsWindows -or $IsWindows -eq $true) {
  if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    # already installed
  } else {
    winget install --id twpayne.chezmoi --source winget
  }
  chezmoi init --apply jetersen
} else {
  Write-Output "This install script is only for Windows."
}
