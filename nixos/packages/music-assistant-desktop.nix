{
  lib,
  stdenvNoCC,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  gtk3,
  webkitgtk_4_1,
  alsa-lib,
  openssl,
  glib-networking,
  libappindicator-gtk3,
  gst_all_1,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "music-assistant-desktop";
  version = "0.7.1";
  src = fetchurl {
    url = "https://github.com/music-assistant/desktop-app/releases/download/${finalAttrs.version}/Music.Assistant_${finalAttrs.version}_amd64.deb";
    hash = "sha256-r6OIQ/2HgYzADOyFQ6i3vGYqYQZpKGlplviAaqRIS0Y=";
  };
  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    wrapGAppsHook3
  ];
  buildInputs = [
    gtk3
    webkitgtk_4_1
    alsa-lib
    openssl
    glib-networking
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
  ];
  unpackPhase = "dpkg-deb -x $src .";
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r usr/* "$out/"
    substituteInPlace "$out/share/applications/Music Assistant.desktop" \
      --replace-fail 'Exec=music-assistant-companion' "Exec=$out/bin/music-assistant-companion"
    runHook postInstall
  '';
  preFixup = ''
    gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libappindicator-gtk3 ]}")
  '';
  meta = {
    description = "Music Assistant desktop client with Sendspin audio playback";
    homepage = "https://github.com/music-assistant/desktop-app";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "music-assistant-companion";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
