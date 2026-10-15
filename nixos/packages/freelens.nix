{
  lib,
  fetchurl,
  appimageTools,
  makeWrapper,
}:
let
  manifest = (builtins.fromJSON (builtins.readFile ./workstation-manifest.json)).freelens;
  pname = "freelens";
  version = lib.removePrefix "v" manifest.version;
  src = fetchurl {
    url = "https://github.com/freelensapp/freelens/releases/download/v${version}/Freelens-${version}-linux-amd64.AppImage";
    sha256 = manifest.sha256;
  };
  contents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  nativeBuildInputs = [ makeWrapper ];
  extraInstallCommands = ''
    install -Dm444 ${contents}/freelens.desktop "$out/share/applications/freelens.desktop"
    substituteInPlace "$out/share/applications/freelens.desktop" \
      --replace-fail 'Exec=AppRun' 'Exec=freelens'
    cp -r ${contents}/usr/share/icons "$out/share/"
    wrapProgram "$out/bin/freelens" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"
  '';
  meta = {
    description = "Free Kubernetes IDE";
    homepage = "https://freelensapp.github.io";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "freelens";
  };
}
