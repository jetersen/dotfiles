@echo off
echo Bootstrapping PowerShell 7...

winget source update --disable-interactivity --ignore-warnings

where pwsh >nul 2>nul
if %errorlevel% neq 0 (
  echo Installing PowerShell 7...
  winget install --id Microsoft.PowerShell --silent --source winget --accept-package-agreements --accept-source-agreements
  echo PowerShell 7 installed!
)

:: Set execution policy for both shells
powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
"%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -NoLogo -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force"
