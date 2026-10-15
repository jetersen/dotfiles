{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  versionCheckHook,
}:
let
  manifest = (builtins.fromJSON (builtins.readFile ./workstation-manifest.json)).codegraph;
in
stdenv.mkDerivation {
  pname = "codegraph";
  version = lib.removePrefix "v" manifest.version;
  src = fetchurl {
    url = "https://github.com/colbymchenry/codegraph/releases/download/${manifest.version}/codegraph-linux-x64.tar.gz";
    sha256 = manifest.sha256;
  };
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontBuild = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/codegraph" "$out/bin"
    cp -r . "$out/lib/codegraph/"
    makeWrapper "$out/lib/codegraph/node" "$out/bin/codegraph" \
      --add-flags '--liftoff-only --disable-warning=ExperimentalWarning' \
      --add-flags "$out/lib/codegraph/lib/dist/bin/codegraph.js" \
      --run 'export CODEGRAPH_HOST_PPID="''${CODEGRAPH_HOST_PPID:-$PPID}"'
    runHook postInstall
  '';
  meta = {
    description = "Local code intelligence and MCP server";
    homepage = "https://github.com/colbymchenry/codegraph";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "codegraph";
  };
}
