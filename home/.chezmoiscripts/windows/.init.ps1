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
# gsudo is needed by the explicit Windows application installation phase.
if (-not (Get-Command "gsudo" -ErrorAction SilentlyContinue)) {
  winget install --id gerardog.gsudo --silent --source winget --accept-package-agreements --accept-source-agreements
}
# SOPS/age and Python are explicit prerequisites, never installed by source reads.
foreach ($tool in @('chezmoi', 'sops', 'age', 'python')) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "Missing prerequisite: $tool"
  }
}
