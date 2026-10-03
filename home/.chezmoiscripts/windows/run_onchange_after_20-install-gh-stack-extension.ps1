if (-not (Get-Command "gh" -ErrorAction SilentlyContinue)) {
  Write-Error "GitHub CLI is required to install the gh-stack extension."
  exit 1
}

$ghStack = gh extension list 2>$null | Select-String -SimpleMatch "github/gh-stack"
if (-not $ghStack) {
  Write-Host "Installing gh-stack GitHub CLI extension..."
  gh extension install github/gh-stack
} else {
  Write-Host "Upgrading gh-stack GitHub CLI extension..."
  gh extension upgrade gh-stack
}
if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to install or upgrade the gh-stack GitHub CLI extension."
  exit $LASTEXITCODE
}
