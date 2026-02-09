#Requires -Version 7

# Get list of installed packages once
$installedPackages = Get-WinGetPackage -Source winget | Select-Object -ExpandProperty Id

function Install-WingetApp {
  param(
    [string]$Id,
    [string]$CustomArgs = "",
    [string]$Source = "winget"
  )

  # Check if package is already installed
  if ($installedPackages -contains $Id) {
    Write-Host "⏭️ $Id already installed, skipping..."
    return
  }

  Write-Host "📦 Installing $Id..."

  Install-WinGetPackage `
    -Id $Id `
    -Mode Silent `
    -Source $Source `
    -AcceptPackageAgreements `
    -AcceptSourceAgreements

  Write-Host "✅ $Id installed!"
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
