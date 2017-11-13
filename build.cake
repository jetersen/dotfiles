#addin "Cake.Powershell"

#load "scripts/utilities.cake"

var target = Argument("target", "Default");
String timeStamp = TimeStamp();
var home = Directory(HomeFolder());

Task("Default")
  .IsDependentOn("git")
  .IsDependentOn("vscode")
  .Does(() =>
{
});

Task("git")
  .Does(() =>
{
  dotfile("git/gitconfig", home);
  dotfile("git/gitconfig.local", home);
  dotfile("git/gitignore.global", home);
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

RunTarget(target);
