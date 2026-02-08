# Check if PowerShell 7 is installed, if not, install it using winget
$pwshPath = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
$scope = Get-ExecutionPolicy -Scope CurrentUser -ErrorAction SilentlyContinue
if (-not [System.IO.File]::Exists($pwshPath)) {
  Write-Host "Installing PowerShell 7..."
  winget install --id Microsoft.PowerShell --silent --source winget --accept-package-agreements --accept-source-agreements
}
if ($scope -ne 'RemoteSigned') {
  try {
    powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>$null
    & $pwshPath -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>$null
  } catch {
    # Silently continue if execution policy setting fails
  }
}
# Check if Proton Pass CLI is installed, if not, install it using winget
if (-not (Get-Command "pass-cli" -ErrorAction SilentlyContinue)) {
  Write-Host "Installing Proton Pass CLI..."
  winget install --id Proton.ProtonPass.CLI --silent --source winget --accept-package-agreements --accept-source-agreements
}
