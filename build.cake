#addin "nuget:?package=Cake.Powershell&version=0.4.7"

#load "scripts/utilities.cake"

var target = Argument("target", "Default");
var home = Directory(HomeFolder());

Task("Default")
  .IsDependentOn("choco")
  .IsDependentOn("git")
  .IsDependentOn("vscode")
  .IsDependentOn("ssh")
  .Does(() =>
{
});

Task("git")
  .Does(() =>
{
  dotfile("git/gitconfig", home);
  dotfile("git/gitconfig.home", home);
  dotfile("git/gitconfig.work", home);
  dotfile("git/gitignore.global", home);
  var githooks = Directory($"{home}/.githooks");
  EnsureDirectoryExists(githooks);
  dotfile("git/hooks/commit-msg", githooks, dotting: false, copy: true);
});

Task("vscode")
  .Does(() =>
{
  var app_home = home;
  if (IsRunningOnWindows()) {
    app_home = Directory($"{EnvironmentVariable("APPDATA")}/Code/User");
  } else if (IsRunningOnLinux()) {
    app_home = Directory($"{home}/.config/Code - OSS/User");
  } else if (IsRunningOnMac()) {
    app_home = Directory($"{home}/Library/Application Support/Code");
  } else {
    return;
  }
  EnsureDirectoryExists(app_home);
  dotfile("vscode/settings.json", app_home, dotting: false);
});

Task("ssh")
  .Does(() =>
{
  var app_home = Directory($"{home}/.ssh");
  EnsureDirectoryExists(app_home);
  dotfile("ssh/config", app_home, dotting: false);
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
