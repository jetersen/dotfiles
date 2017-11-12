Func<String> HomeFolder = () => {
  string home;
  if(IsRunningOnWindows()) {
    home = $"{EnvironmentVariable("HOMEDRIVE")}{EnvironmentVariable("HOMEPATH")}";
  } else {
    home = EnvironmentVariable("HOME");
  }
  return home;
};

Func<String> TimeStamp = () => {
    return Math.Floor((DateTime.UtcNow.Subtract(new DateTime(1970, 1, 1))).TotalSeconds).ToString();
};
