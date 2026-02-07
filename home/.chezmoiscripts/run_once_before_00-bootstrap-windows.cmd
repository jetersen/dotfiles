@echo off
echo Bootstrapping PowerShell 7...

where pwsh >nul 2>nul
if %errorlevel% neq 0 (
  echo Installing PowerShell 7...
  winget install --id Microsoft.PowerShell --silent --source winget --accept-package-agreements --accept-source-agreements
  echo PowerShell 7 installed!
)

:: Set execution policy for both shells
powershell -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>nul
"%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -NoLogo -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>nul
exit /b 0
