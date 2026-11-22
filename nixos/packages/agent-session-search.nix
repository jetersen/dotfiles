{
  lib,
  stdenv,
  stdenvNoCC,
  autoPatchelfHook,
  makeWrapper,
  runCommand,
  agentsviewArchive,
  agentsviewVersion,
  kennembedArchive,
  kennembedVersion,
  modelFile,
  tokenizerFile,
  modelRevision,
}:
let
  modelRoot = "nomic-embed-text-v1.5/${modelRevision}";
in
{
  agentsview = stdenvNoCC.mkDerivation {
    pname = "agentsview";
    version = agentsviewVersion;
    src = agentsviewArchive;
    unpackCmd = ''tar -xzf "$curSrc"'';
    sourceRoot = ".";
    dontBuild = true;
    nativeBuildInputs = [ autoPatchelfHook ];
    buildInputs = [ stdenv.cc.cc.lib ];
    installPhase = ''
      runHook preInstall
      install -Dm755 agentsview "$out/bin/agentsview"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      "$out/bin/agentsview" --version | grep -F 'agentsview v${agentsviewVersion}'
    '';
    meta = {
      description = "Private coding-agent session search and archive";
      homepage = "https://github.com/kenn-io/agentsview";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "agentsview";
    };
  };
  kennembed = stdenvNoCC.mkDerivation {
    pname = "kennembed";
    version = kennembedVersion;
    src = kennembedArchive;
    unpackCmd = ''tar -xzf "$curSrc"'';
    sourceRoot = ".";
    dontBuild = true;
    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = [ stdenv.cc.cc.lib ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/kennembed" "$out/bin"
      cp kennembed *.so* "$out/lib/kennembed/"
      mkdir -p "$out/share/doc/kennembed"
      cp *LICENSE ThirdPartyNotices.txt "$out/share/doc/kennembed/"
      makeWrapper "$out/lib/kennembed/kennembed" "$out/bin/kennembed"
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      "$out/bin/kennembed" -help
    '';
    meta = {
      description = "Local ONNX embedding runtime";
      homepage = "https://github.com/kenn-io/kit";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "kennembed";
    };
  };
  nomic-embed-text =
    runCommand "nomic-embed-text-v1.5-${modelRevision}" { passthru = { inherit modelRoot; }; }
      ''
        mkdir -p "$out/${modelRoot}"
        ln -s ${modelFile} "$out/${modelRoot}/model.onnx"
        ln -s ${tokenizerFile} "$out/${modelRoot}/tokenizer.json"
      '';
}
