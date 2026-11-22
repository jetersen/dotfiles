{
  lib,
  src,
  version,
  appimageTools,
  makeWrapper,
}:
let
  pname = "freelens";
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
