{
  lib,
  stdenv,
  appimageTools,
  autoPatchelfHook,
  musl,
  vulkan-loader,
  symlinkJoin,
  makeWrapper,
  git,
  gh,
  fish,
  codex,
  claude-code,
  cliArchive,
  cliUrl,
  desktopImage,
  desktopUrl,
}:
let
  releaseUrl = "https://github.com/pingdotgg/t3code/releases/download";
  cliVersions = builtins.match "${releaseUrl}/v([0-9]+[.][0-9]+[.][0-9]+)/t3-([0-9]+[.][0-9]+[.][0-9]+)-linux-x64[.]tar[.]gz" cliUrl;
  version = builtins.head cliVersions;
  runtimePackages = [
    git
    gh
    fish
    codex
    claude-code
  ];
  cli = stdenv.mkDerivation {
    pname = "t3";
    inherit version;
    src = cliArchive;
    # Non-flake file inputs have no filename extension in the store.
    unpackCmd = ''mkdir source; tar -xzf "$curSrc" -C source --strip-components=1'';
    sourceRoot = "source";
    dontBuild = true;
    # The standalone executable contains its JavaScript payload after the ELF data.
    dontStrip = true;
    nativeBuildInputs = [
      autoPatchelfHook
      makeWrapper
    ];
    # Upstream bundles both glibc and musl native modules.
    buildInputs = [
      stdenv.cc.cc.lib
      musl
      vulkan-loader
    ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/t3" "$out/bin"
      cp -r . "$out/lib/t3/"
      chmod -R u+w "$out/lib/t3"
      makeWrapper "$out/lib/t3/t3" "$out/bin/t3" \
        --set T3CODE_DISABLE_AUTO_UPDATE 1 \
        --prefix PATH : ${lib.makeBinPath runtimePackages}
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test "$("$out/bin/t3" --version)" = "t3 v${version}"
      runHook postInstallCheck
    '';
  };
  desktopContents = appimageTools.extract {
    pname = "t3code-desktop";
    inherit version;
    src = desktopImage;
  };
  desktop = appimageTools.wrapAppImage {
    pname = "t3code-desktop";
    inherit version;
    src = desktopContents;
    extraPkgs = _: runtimePackages;
    profile = ''
      export T3CODE_DISABLE_AUTO_UPDATE=1
      export PATH=${lib.makeBinPath runtimePackages}:"$PATH"
    '';
  };
in
assert lib.assertMsg (
  cliVersions != null
  && version == builtins.elemAt cliVersions 1
  && desktopUrl == "${releaseUrl}/v${version}/T3-Code-x86_64.AppImage"
) "The T3 Code CLI and desktop inputs must select the same release.";
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
  meta = {
    description = "T3 Code desktop and CLI from the same upstream release";
    homepage = "https://github.com/pingdotgg/t3code";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "t3code-desktop";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
