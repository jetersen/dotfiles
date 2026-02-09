#Requires -Version 7

# Disable UAC to prevent prompts during installations
gsudo cache on
gsudo Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 0
Write-Host "🔓 UAC temporarily disabled for installations"

# Get list of installed packages once
$installedPackages = winget list --source winget --accept-source-agreements | Out-String

function Install-WingetApp {
  param(
    [string]$Id,
    [string]$CustomArgs = "",
    [string]$Source = "winget"
  )

  # Check if package is already installed
  if ($installedPackages -match [regex]::Escape($Id)) {
    Write-Host "⏭️ $Id already installed, skipping..."
    return
  }

  Write-Host "📦 Installing $Id..."

  $wingetArgs = @(
    "install"
    "--id", $Id
    "--silent"
    "--source", $Source
    "--accept-package-agreements"
    "--accept-source-agreements"
  )

  if ($CustomArgs -ne "") {
    $wingetArgs += "--custom"
    $wingetArgs += $CustomArgs
  }

  winget @wingetArgs

  if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ $Id installed!"
  } else {
    Write-Host "❌ $Id failed to install (exit code: $LASTEXITCODE)"
  }
}

$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

Install-WingetApp -Id "Amazon.AWSCli"
Install-WingetApp -Id "dandavison.delta"
Install-WingetApp -Id "Flameshot.Flameshot"
Install-WingetApp -Id "gerardog.gsudo"
Install-WingetApp -Id "Git.Git" -CustomArgs '/components="gitlfs" /o:EditorOption=VisualStudioCode /o:CURLOption=WinSSL'
Install-WingetApp -Id "GitHub.cli"
Install-WingetApp -Id "JanDeDobbeleer.OhMyPosh"
Install-WingetApp -Id "Microsoft.DotNet.SDK.10"
Install-WingetApp -Id "Microsoft.PowerShell"
Install-WingetApp -Id "Microsoft.VisualStudioCode"
Install-WingetApp -Id "Mirantis.Lens"
Install-WingetApp -Id "OlegDanilov.RapidEnvironmentEditor"
Install-WingetApp -Id "OpenVPNTechnologies.OpenVPNConnect"
Install-WingetApp -Id "SecretsOPerationS.SOPS"
Install-WingetApp -Id "SlackTechnologies.Slack"
Install-WingetApp -Id "UderzoSoftware.SpaceSniffer"
Install-WingetApp -Id "WinSCP.WinSCP"
Install-WingetApp -Id "Yubico.Authenticator"

# Re-enable UAC
gsudo Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1
Write-Host "🔒 UAC re-enabled"
