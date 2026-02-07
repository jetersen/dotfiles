Write-Host "🥳 First install, let's get you setup!" -ForegroundColor Magenta

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
  Write-Host "📦 Installing Git..."
  winget install --id Git.Git `
    --custom '/components="gitlfs" /o:EditorOption=VisualStudioCode /o:CURLOption=WinSSL /o:UseCredentialManager=Enabled' `
    --silent --source winget --accept-package-agreements --accept-source-agreements
  Write-Host "✅ Git installed!"
}

if (-not (Get-Command "gsudo" -ErrorAction SilentlyContinue)) {
  Write-Host "📦 Installing gsudo..."
  winget install --id gerardog.gsudo `
    --silent --source winget --accept-package-agreements --accept-source-agreements
  Write-Host "✅ gsudo installed!"
}

if (-not (Get-Command "delta" -ErrorAction SilentlyContinue)) {
  Write-Host "📦 Installing delta..."
  winget install --id dandavison.delta `
    --silent --source winget --accept-package-agreements --accept-source-agreements
  Write-Host "✅ delta installed!"
}

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
