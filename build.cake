#addin "Cake.FileHelpers"
#addin "Cake.Powershell"

#load "scripts/utilities.cake"

var target = Argument("target", "Default");
String timeStamp = TimeStamp();
var home = Directory(HomeFolder());

Action<string, string> SymLinkFile = (source, link) => {
  if (IsRunningOnWindows()) {
    StartPowershellScript("New-Item", new PowershellSettings()
      .WithArguments(args => {
        args.Append("ItemType", "SymbolicLink")
            .Append("Target", source)
            .Append("Path", link);
      }));
  } else if (IsRunningOnUnix()) {
    var process = "ln";
    var arguments = $"-s {source} {link}";
    Information("process: {0}, args: {1}", process, arguments);
    var exitCodeWithArgument = StartProcess(process);
    Information("Exit code: {0}", exitCodeWithArgument);
  } else {
    return;
  }
};

Action<string, string> dotfile = (source, dest) => {
  var directory = Directory(dest);
  var repo_file = File($"./{source}");
  var dotfile = $".{source.Split('/').Last()}";
  var link = directory + File(dotfile);
  if (FileExists(link))
  {
    var old = directory + File($"{dotfile}.{timeStamp}.old");
    MoveFile(link, old);
  }
  SymLinkFile(repo_file, link);
};

Task("Default")
  .IsDependentOn("git")
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

RunTarget(target);
