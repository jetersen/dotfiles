$ErrorActionPreference = 'Stop'

if ($null -eq $IsWindows -or $IsWindows -eq $true) {
  if (Get-Command chezmoi -ErrorAction SilentlyContinue) {
    # already installed
  } else {
    winget install --id twpayne.chezmoi --source winget
  }
  chezmoi init --apply jetersen
  # Re-apply so scripts that require pwsh (installed by bootstrap) can run
  $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
  chezmoi apply
} else {
  Write-Output "This install script is only for Windows."
}
