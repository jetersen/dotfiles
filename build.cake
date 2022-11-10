#load "scripts/utilities.cake"

var target = Argument("target", "Default");
var home = Directory(HomeFolder());

Task("Default")
  .IsDependentOn("git")
  .IsDependentOn("ssh")
  .IsDependentOn("powershell")
  .IsDependentOn("zsh")
  .IsDependentOn("oh-my-posh")
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
  dotfile("git/gitconfig.codespaces", home);
  var githooks = Directory($"{home}/.githooks");
  EnsureDirectoryExists(githooks);
  dotfile("git/hooks/commit-msg", githooks, dotting: false, copy: true);
});

Task("ssh")
  .Does(() =>
{
  var app_home = Directory($"{home}/.ssh");
  EnsureDirectoryExists(app_home);
  dotfile("ssh/config", app_home, dotting: false, copy: true);
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

Task("oh-my-posh")
  .Does(() =>
{
  dotfile("oh-my-posh/jetersen.omp.json", home);
});

RunTarget(target);
