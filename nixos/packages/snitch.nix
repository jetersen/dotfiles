{
  lib,
  buildDotnetModule,
  dotnet-sdk_10,
  source,
}:
let
  version = "2.1.0-local.2";
  common = {
    inherit version;
    src = source;
    # Nix builds the CLI directly; the upstream Cake release tool is unnecessary.
    postPatch = "rm dotnet-tools.json";
    projectFile = "src/Snitch/Snitch.csproj";
    dotnet-sdk = dotnet-sdk_10;
  };
  nugetFeed = buildDotnetModule (
    common
    // {
      pname = "snitch-nuget-feed";
      keepNugetConfig = true;
      dotnetRestoreFlags = [
        "--source"
        "https://api.nuget.org/v3/index.json"
      ];
      dontBuild = true;
      dontFixup = true;
      # Store the packages only; NuGet's local cache metadata contains build paths.
      installPhase = ''
        mkdir -p "$out"
        find "$NUGET_PACKAGES" -type f -name '*.nupkg' -exec cp -t "$out" {} +
      '';
      outputHashMode = "recursive";
      outputHash = "sha256-I81ehmTOdHj6IAp8tgny/o6WqaMwgkR4PQhFrCgJ4bA=";
    }
  );
in
buildDotnetModule (
  common
  // {
    pname = "snitch";
    dotnetRestoreFlags = [
      "--source"
      "${nugetFeed}"
    ];
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
)
