#addin "Cake.Powershell"

#load "scripts/utilities.cake"

var target = Argument("target", "Default");
var home = Directory(HomeFolder());

var vscodeExtensions = new string[] {
  "cake-build.cake-vscode",
  "chenxsan.vscode-standard-format",
  "chenxsan.vscode-standardjs",
  "EditorConfig.EditorConfig",
  "mathiasfrohlich.Kotlin",
  "mikestead.dotenv",
  "ms-vscode.csharp",
  "ms-vscode.PowerShell",
  "PeterJausovec.vscode-docker",
};

Task("Default")
  .IsDependentOn("choco")
  .IsDependentOn("git")
  .IsDependentOn("vscode")
  .IsDependentOn("vscode-extensions")
  .IsDependentOn("ssh")
  .Does(() =>
{
});

Task("git")
  .Does(() =>
{
  dotfile("git/gitconfig", home);
  dotfile("git/gitconfig.local", home, true, true, false);
  dotfile("git/gitignore.global", home);
  var githooks = Directory($"{home}/.githooks");
  EnsureDirectoryExists(githooks);
  dotfile("git/hooks/commit-msg", githooks, false, true);
});

Task("vscode")
  .Does(() =>
{
  var app_home = home;
  if (IsRunningOnWindows())
  {
    app_home = Directory($"{EnvironmentVariable("APPDATA")}/Code/User");
  } else if (IsRunningOnLinux()) {
    app_home = Directory($"{home}/.config/Code");
  } else if (IsRunningOnMac()) {
    app_home = Directory($"{home}/Library/Application Support/Code");
  } else {
    return;
  }
  EnsureDirectoryExists(app_home);
  dotfile("vscode/settings.json", app_home, false);
});

Task("vscode-extensions")
  .Does(() =>
{
  foreach (var extension in vscodeExtensions)
  {
    StartProcess("code", new ProcessSettings
    {
      Arguments = new ProcessArgumentBuilder()
        .Append("--install-extension")
        .Append(extension)
    });
  }
});

Task("ssh")
  .Does(() =>
{
  var app_home = Directory($"{home}/.ssh");
  EnsureDirectoryExists(app_home);
  dotfile("ssh/config", app_home, false);
});

/// <summary>
/// When you cannot get enough package managers 🤣
/// </summary>
Task("choco")
  .WithCriteria(IsRunningOnWindows())
  .WithCriteria(
    !DirectoryExists($"{EnvironmentVariable("HOMEDRIVE")}/ProgramData/chocolatey")
    ||
    !HasEnvironmentVariable("ChocolateyInstall"))
  .Does(() =>
{
  StartPowershellScript("Start-Process", args => {
    args
      .Append("powershell")
      .Append("Verb", "Runas")
      .AppendStringLiteral(
        "ArgumentList", "Set-ExecutionPolicy Bypass -Scope Process -Force; " +
        "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))"
      );
  });
});

Task("CodePage")
  .WithCriteria(IsRunningOnWindows())
  .Does(() =>
{
  StartPowershellScript("sp -t d HKCU:\\Console CodePage 0xfde9");
});


RunTarget(target);
