#load "scripts/utilities.cake"

var target = Argument("target", "Default");
var home = Directory(HomeFolder());

Task("Default")
  .IsDependentOn("git")
  .IsDependentOn("vscode")
  .IsDependentOn("ssh")
  .IsDependentOn("powershell")
  .IsDependentOn("zsh")
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
    app_home = Directory($"{home}/.config/Code/User");
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

Task("pwsh")
  .WithCriteria(OnPath("pwsh"))
  .Does(() =>
{
  SymLinkProfile("pwsh", "powershell/profile.ps1");
});

Task("powershellv5")
  .WithCriteria(OnPath("powershell"))
  .Does(() =>
{
  SymLinkProfile("powershell", "powershell/profile.ps1");
});

Task("powershell")
  .IsDependentOn("pwsh")
  .IsDependentOn("powershellv5");

Task("zsh")
  .Does(() =>
{
  dotfile("zsh/zshrc", home);
  dotfile("zsh/zprofile", home);
});

RunTarget(target);
