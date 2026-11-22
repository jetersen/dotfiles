{
  lib,
  stdenv,
  src,
  version,
  autoPatchelfHook,
  makeWrapper,
  openssl,
  zlib,
  libsecret,
  versionCheckHook,
}:
stdenv.mkDerivation {
  pname = "varlock";
  inherit src version;
  unpackCmd = ''tar -xzf "$curSrc"'';
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
