{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  manifest = (builtins.fromJSON (builtins.readFile ./workstation-manifest.json)).proton-ge;
in
stdenvNoCC.mkDerivation {
  pname = "proton-ge";
  version = manifest.version;
  src = fetchurl {
    url = "https://github.com/${manifest.repo}/releases/download/${manifest.version}/${manifest.version}-x86_64.tar.gz";
    sha512 = manifest.sha512;
  };
  outputs = [
    "out"
    "steamcompattool"
  ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    echo 'Use programs.steam.extraCompatPackages to install this tool.' > "$out"
    mkdir -p "$steamcompattool"
    cp -a . "$steamcompattool/"
    # Keep Steam's selected tool name stable across GE release updates.
    substituteInPlace "$steamcompattool/compatibilitytool.vdf" \
      --replace-fail '${manifest.version}-x86_64' 'GE-Proton'
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$steamcompattool/proton"
    grep -q '"GE-Proton"' "$steamcompattool/compatibilitytool.vdf"
  '';
  meta = {
    description = "Upstream GE-Proton compatibility tool for Steam";
    homepage = "https://github.com/GloriousEggroll/proton-ge-custom";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
