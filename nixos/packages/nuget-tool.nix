{
  pkgs,
  lib,
  source,
  version,
  pname,
  nugetName,
}:
let
  buildTool = pkgs.callPackage "${pkgs.path}/pkgs/build-support/dotnet/build-dotnet-global-tool" {
    # The flake locks the official NuGet archive, including its content hash.
    fetchNupkg = attrs: (pkgs.dotnetCorePackages.fetchNupkg attrs).overrideAttrs { src = source; };
  };
in
buildTool {
  inherit pname nugetName version;
  dotnet-sdk = pkgs.dotnet-sdk_10;
  dotnet-runtime = pkgs.dotnet-sdk_10;
  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  doInstallCheck = true;
  versionCheckProgramArg = if pname == "dotnet-lambda" then "--help" else "--version";
  # Allow these tools' older target frameworks to use the installed stable SDK.
  postInstall = ''
    while IFS= read -r -d "" file; do
      ${lib.getExe pkgs.jq} '.runtimeOptions.rollForward = "Major"' "$file" > "$file.tmp"
      mv "$file.tmp" "$file"
    done < <(find "$out/lib/${pname}" -name '*.runtimeconfig.json' -print0)
  '';
  meta = {
    description = "Nix-managed ${nugetName} global tool";
    homepage = "https://www.nuget.org/packages/${nugetName}";
    license = if nugetName == "Amazon.Lambda.Tools" then lib.licenses.asl20 else lib.licenses.mit;
    mainProgram = pname;
    platforms = lib.platforms.linux;
  };
}
