{
  lib,
  buildDotnetModule,
  dotnet-sdk_10,
  source,
}:
buildDotnetModule {
  pname = "snitch";
  version = "2.1.0-local.2";
  src = source;
  # Nix builds the CLI directly; the upstream Cake release tool is unnecessary.
  postPatch = "rm dotnet-tools.json";
  projectFile = "src/Snitch/Snitch.csproj";
  nugetDeps = ./snitch-deps.json;
  dotnet-sdk = dotnet-sdk_10;
  # Buildalyzer needs the SDK/MSBuild to inspect the user's projects.
  dotnet-runtime = dotnet-sdk_10;
  useDotnetFromEnv = true;
  executables = [ "Snitch" ];
  postFixup = ''
    mv "$out/bin/Snitch" "$out/bin/snitch"
  '';
  meta = {
    description = "Find redundant transitive .NET package references";
    homepage = "https://github.com/jetersen/snitch";
    license = lib.licenses.mit;
    mainProgram = "snitch";
    platforms = lib.platforms.linux;
  };
}
