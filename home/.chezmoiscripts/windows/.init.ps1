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
if (-not (Get-Command "gsudo" -ErrorAction SilentlyContinue)) {
  Write-Host "Installing gsudo..."
  winget install --id gerardog.gsudo --silent --source winget --accept-package-agreements --accept-source-agreements
}
# Check login status of Proton Pass CLI, if not logged in, prompt the user to log in
pass-cli test >$null 2>&1
if ($LASTEXITCODE -ne 0) {
  Write-Host "Please log in to Proton Pass CLI..."
  pass-cli login
}
