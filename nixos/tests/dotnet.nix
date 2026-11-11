{
  pkgs,
  inputs,
  configurations,
}:
let
  sdk = inputs.self.packages.x86_64-linux.dotnet-sdk;
in
assert builtins.all
  (
    host:
    let
      home = configurations.${host}.config.home-manager.users.joseph;
    in
    builtins.elem sdk home.home.packages
    && home.home.sessionVariables.DOTNET_ROOT == "${sdk}/share/dotnet"
  )
  [
    "rocket"
    "framework"
  ];
pkgs.runCommand "dotnet-sdk-smoke" { nativeBuildInputs = [ sdk ]; } ''
  export HOME="$TMPDIR/home"
  export DOTNET_ROOT=${sdk}/share/dotnet
  export DOTNET_CLI_TELEMETRY_OPTOUT=1
  export DOTNET_NOLOGO=1
  mkdir -p "$HOME"
  test "$(dotnet --version)" = 11.0.100
  dotnet --list-sdks | grep '^10\.'
  dotnet --list-runtimes | grep '^Microsoft.AspNetCore.App 11.0.0 '
  for version in 11.0.100 ${pkgs.dotnet-sdk_10.version}; do
    mkdir "$version"
    (
      cd "$version"
      printf '{"sdk":{"version":"%s","rollForward":"disable"}}' "$version" > global.json
      test "$(dotnet --version)" = "$version"
      dotnet new console --no-restore
      dotnet restore --source "$TMPDIR/empty-feed" -p:NuGetAudit=false
      dotnet run --no-restore > result
      grep -Fx 'Hello, World!' result
    )
  done
  touch "$out"
''
