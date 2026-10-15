{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  manifest = (builtins.fromJSON (builtins.readFile ./workstation-manifest.json)).topf;
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "topf";
  version = lib.removePrefix "v" manifest.version;
  src = fetchurl {
    url = "https://github.com/postfinance/topf/releases/download/v${finalAttrs.version}/topf_linux_amd64.tar.gz";
    sha256 = manifest.sha256;
  };
  sourceRoot = ".";
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 topf "$out/bin/topf"
    runHook postInstall
  '';
  meta = {
    description = "Talos orchestrator by PostFinance";
    homepage = "https://github.com/postfinance/topf";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "topf";
  };
})
