using System.Runtime.InteropServices;

var renew = EnvironmentVariable("renew")?.Equals("1") ?? false;

string HomeFolder() {
  string home;
  if(IsRunningOnWindows()) {
    home = $"{EnvironmentVariable("HOMEDRIVE")}{EnvironmentVariable("HOMEPATH")}";
  } else {
    home = EnvironmentVariable("HOME");
  }
  return home;
}

string TimeStamp() {
    return Math.Floor((DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1))).TotalSeconds).ToString();
}

void dotfile(string source, string dest, bool dotting = true, bool copy = false) {
  var directory = Directory(dest);
  var repo_file = MakeAbsolute(File($"./{source}")).FullPath;
  var dot = dotting ? "." : "";
  var file = $"{dot}{source.Split('/').Last()}";
  var link = directory + File(file);
  if (FileExists(link) && renew)
  {
    if (copy) {
      var old = directory + File($"{file}.{TimeStamp()}.old");
      MoveFile(link, old);
    } else DeleteFile(link);
  } else {
    if (copy) CopyFile(repo_file, link);
    else SymLinkFile(repo_file, link);
  }
}

void SymLinkFile(string source, string link) {
  var process = "";
  var arguments = "";
  if (IsRunningOnWindows()) {
    process = "powershell.exe";
    var script = $"New-Item -Force -ItemType SymbolicLink -Target {source.Quote()} -Path {link.Quote()} | Out-Null";
    arguments = $"-noprofile -c {script.Quote()}";
  } else if (IsRunningOnUnix()) {
    process = "ln";
    arguments = $"-s {source.Quote()} {link.Quote()}";
  }
  RunProcess(process, arguments);
}

void SymLinkProfile(string process, string source) {
  var repo_file = MakeAbsolute(File(source)).FullPath;
  var script = $"New-Item -Force -ItemType SymbolicLink -Target {repo_file.Quote()} -Path \"$profile\" | Out-Null";
  var arguments = $"-noprofile -c {script.Quote()}";
  RunProcess(process, arguments);
  SymLinkVSCodeProfile(process, source);
}

void SymLinkVSCodeProfile(string process, string source) {
  var repo_file = MakeAbsolute(File(source)).FullPath;
  var script =
    "$p = $profile | Split-Path -Parent; $vsCodeProfile = Join-Path $p 'Microsoft.VSCode_profile.ps1';" +
    $"New-Item -Force -ItemType SymbolicLink -Target {repo_file.Quote()} -Path \"$vsCodeProfile\" | Out-Null";
  var arguments = $"-noprofile -c {script.Quote()}";
  RunProcess(process, arguments);
}

void RunProcess(string process, string arguments) {
  Information($"process: {process}, args: {arguments}");
  var exitCodeWithArgument = StartProcess(process, arguments);
  Information($"Exit code: {exitCodeWithArgument}");
}

bool OnPath(string process, string arguments = "-h -noprofile") {
  var available = 1;
  try {
    available = StartProcess(process, new ProcessSettings {
      Arguments = arguments,
      RedirectStandardOutput = true
    });
  } catch {}
  return available == 0;
}

internal static class MacPlatformDetector {
    internal static readonly Lazy<bool> IsMac = new Lazy<bool>(IsRunningOnMac);

    [DllImport("libc")]
    static extern int uname(IntPtr buf);

    static bool IsRunningOnMac() {
        IntPtr buf = IntPtr.Zero;
        try {
            buf = Marshal.AllocHGlobal(8192);
            // This is a hacktastic way of getting sysname from uname()
            if (uname(buf) == 0) {
                string os = Marshal.PtrToStringAnsi(buf);
                if (os == "Darwin") return true;
            }
        } catch {
        } finally {
            if (buf != IntPtr.Zero) Marshal.FreeHGlobal(buf);
        }
        return false;
    }
}

bool IsRunningOnMac() {
    return System.Environment.OSVersion.Platform == PlatformID.MacOSX || MacPlatformDetector.IsMac.Value;
}

bool IsRunningOnLinux() {
    return IsRunningOnUnix() && !IsRunningOnMac();
}
