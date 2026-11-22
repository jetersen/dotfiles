{
  lib,
  stdenvNoCC,
  src,
  version,
}:
stdenvNoCC.mkDerivation {
  pname = "topf";
  inherit src version;
  unpackCmd = ''tar -xzf "$curSrc"'';
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
}
