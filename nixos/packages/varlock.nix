{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  openssl,
  zlib,
  libsecret,
  versionCheckHook,
}:
let
  manifest = (builtins.fromJSON (builtins.readFile ./workstation-manifest.json)).varlock;
in
stdenv.mkDerivation {
  pname = "varlock";
  version = lib.removePrefix "varlock@" manifest.version;
  src = fetchurl {
    url = "https://github.com/dmno-dev/varlock/releases/download/${manifest.version}/varlock-linux-x64.tar.gz";
    sha256 = manifest.sha256;
  };
  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    openssl
    zlib
    libsecret
  ];
  sourceRoot = ".";
  dontBuild = true;
  # Stripping a Bun standalone executable discards its embedded JavaScript.
  dontStrip = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  doInstallCheck = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 varlock "$out/bin/varlock"
    install -Dm755 varlock-local-encrypt "$out/bin/varlock-local-encrypt"
    runHook postInstall
  '';
  meta = {
    description = "Schema-based environment loading from password managers";
    homepage = "https://varlock.dev";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "varlock";
  };
}
