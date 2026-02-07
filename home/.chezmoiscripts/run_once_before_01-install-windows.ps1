#Requires -Version 7

function Install-WingetPackage {
  param(
    [string]$Id,
    [string]$Command = "",
    [string]$CustomArgs = "",
    [string]$Source = "winget"
  )

  $Name = $Id.Substring($Id.LastIndexOf('.') + 1)

  $CommandName = if ($Command) { $Command } else { $Name.ToLowerInvariant() }

  if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
    return
  }

  $wingetArgs = @(
    "install",
    "--id", $Id,
    "--silent",
    "--source", $Source,
    "--accept-package-agreements",
    "--accept-source-agreements"
  )

  if ($CustomArgs) {
    $wingetArgs += "--custom", $CustomArgs
  }

  Write-Host "📦 Installing $Name..."
  winget @wingetArgs
  Write-Host "✅ $Name installed!"
}

Write-Host "🥳 First install, let's get you setup!" -ForegroundColor Magenta

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Install-WingetPackage -Id "Git.Git" -CustomArgs '/components="gitlfs" /o:EditorOption=VisualStudioCode /o:CURLOption=WinSSL /o:UseCredentialManager=Enabled'
Install-WingetPackage -Id "gerardog.gsudo"
Install-WingetPackage -Id "dandavison.delta"

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
