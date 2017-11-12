using System.Runtime.InteropServices;

string HomeFolder()
{
  string home;
  if(IsRunningOnWindows())
  {
    home = $"{EnvironmentVariable("HOMEDRIVE")}{EnvironmentVariable("HOMEPATH")}";
  }
  else
  {
    home = EnvironmentVariable("HOME");
  }
  return home;
}

string TimeStamp()
{
    return Math.Floor((DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1))).TotalSeconds).ToString();
}

void SymLinkFile(string source, string link)
{
  if (IsRunningOnWindows())
  {
    StartPowershellScript("New-Item", new PowershellSettings()
      .WithArguments(args => {
        args.Append("ItemType", "SymbolicLink")
            .Append("Target", source)
            .Append("Path", link);
      }));
  }
  else if (IsRunningOnUnix())
  {
    var process = "ln";
    var arguments = $"-s {source} {link}";
    Information("process: {0}, args: {1}", process, arguments);
    var exitCodeWithArgument = StartProcess(process);
    Information("Exit code: {0}", exitCodeWithArgument);
  } else
    return;
}

internal static class MacPlatformDetector
{
    internal static readonly Lazy<bool> IsMac = new Lazy<bool>(IsRunningOnMac);

    [DllImport("libc")]
    static extern int uname(IntPtr buf);

    static bool IsRunningOnMac()
    {
        IntPtr buf = IntPtr.Zero;
        try {
            buf = Marshal.AllocHGlobal(8192);
            // This is a hacktastic way of getting sysname from uname()
            if (uname(buf) == 0) {
                string os = Marshal.PtrToStringAnsi(buf);
                if (os == "Darwin")
                    return true;
            }
        } catch {
        } finally {
            if (buf != IntPtr.Zero)
                Marshal.FreeHGlobal(buf);
        }
        return false;
    }
}

bool IsRunningOnMac()
{
    return System.Environment.OSVersion.Platform == PlatformID.MacOSX || MacPlatformDetector.IsMac.Value;
}

bool IsRunningOnLinux()
{
    return IsRunningOnUnix() && !IsRunningOnMac();
}
