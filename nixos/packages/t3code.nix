{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  appimageTools,
  autoPatchelfHook,
  symlinkJoin,
  makeWrapper,
  git,
  gh,
  fish,
  codex,
  claude-code,
  callPackage,
  asar,
  python3,
  writeShellScriptBin,
}:
let
  manifest = (builtins.fromJSON (builtins.readFile ./workstation-manifest.json)).t3code;
  version = lib.removePrefix "v" manifest.version;
  backgroundGh = writeShellScriptBin "gh" ''
    exec ${python3.withPackages (ps: [ ps.dbus-python ])}/bin/python3 ${./t3-gh.py} ${gh}/bin/gh "$@"
  '';
  runtimePackages = [
    git
    backgroundGh
    fish
    codex
    claude-code
  ];
  cliSource = stdenvNoCC.mkDerivation {
    pname = "t3code-cli-source";
    inherit version;
    src = fetchurl {
      url = "https://github.com/${manifest.repo}/releases/download/v${version}/t3-${version}-linux-x64.tar.gz";
      sha256 = manifest.cliSha256;
    };
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out"
      cp -r . "$out/"
    '';
  };
  web = callPackage ./t3code-web.nix { releaseClient = "${cliSource}/client"; };
  cli = stdenv.mkDerivation {
    pname = "t3";
    inherit version;
    src = cliSource;
    dontUnpack = true;
    dontBuild = true;
    # The standalone executable contains its JavaScript payload after the ELF data.
    dontStrip = true;
    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];
    buildInputs = [ stdenv.cc.cc.lib ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/t3" "$out/bin"
      cp -r "$src/"* "$out/lib/t3/"
      chmod -R u+w "$out/lib/t3"
      rm -r "$out/lib/t3/client"
      cp -r ${web} "$out/lib/t3/client"
      makeWrapper "$out/lib/t3/t3" "$out/bin/t3" \
        --set T3CODE_DISABLE_AUTO_UPDATE 1 \
        --prefix PATH : ${lib.makeBinPath runtimePackages}
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      "$out/bin/t3" --version
      runHook postInstallCheck
    '';
  };
  desktopImage = fetchurl {
    url = "https://github.com/${manifest.repo}/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    sha256 = manifest.desktopSha256;
  };
  desktopContents = appimageTools.extract {
    pname = "t3code-desktop";
    inherit version;
    src = desktopImage;
  };
  patchedDesktopContents = stdenvNoCC.mkDerivation {
    pname = "t3code-desktop-shared-browser";
    inherit version;
    src = desktopContents;
    nativeBuildInputs = [
      asar
      python3
    ];
    dontBuild = true;
    installPhase = ''
      cp -r . "$out"
      chmod -R u+w "$out"
      # Retain the release's native-module unpacking layout.
      unpacked=$(python3 ${./t3code-unpacked.py} "$out/resources/app.asar")
      asar extract "$out/resources/app.asar" app
      rm -r app/apps/server/dist/client
      cp -r ${web} app/apps/server/dist/client
      rm -r "$out/resources/app.asar" "$out/resources/app.asar.unpacked"
      asar pack app "$out/resources/app.asar" --unpack-dir "$unpacked"
    '';
  };
  desktop = appimageTools.wrapAppImage {
    pname = "t3code-desktop";
    inherit version;
    src = patchedDesktopContents;
    extraPkgs = _: runtimePackages;
    profile = ''
      export T3CODE_DISABLE_AUTO_UPDATE=1
      export PATH=${lib.makeBinPath runtimePackages}:"$PATH"
    '';
  };
in
assert lib.assertMsg (
  version == web.version
) "Rebase the T3 shared-browser renderer patch before updating T3.";
symlinkJoin {
  name = "t3code-${version}";
  inherit version;
  paths = [
    cli
    desktop
  ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    # T3's generated desktop/URL handler must launch the Nix FHS wrapper.
    wrapProgram "$out/bin/t3code-desktop" --set APPIMAGE "$out/bin/t3code-desktop"
    # Keep all historical entry points selecting the same release.
    ln -s "$out/bin/t3" "$out/bin/t3code"
    mkdir -p "$out/share/applications"
    substitute ${desktopContents}/t3code.desktop "$out/share/applications/t3code.desktop" \
      --replace-fail 'Exec=AppRun %U' "Exec=$out/bin/t3code-desktop %U"
    install -Dm644 ${desktopContents}/t3code.png "$out/share/pixmaps/t3code.png"
  '';
  passthru = { inherit cliSource web; };
  meta = {
    description = "T3 Code desktop and CLI from the same upstream release";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3code-desktop";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
