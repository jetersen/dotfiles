{
  jetbrains,
  fetchurl,
  curl,
  libsecret,
  libsoup_3,
  webkitgtk_4_1,
}:
# Keep nixpkgs' launcher, desktop integration and native-library fixes while
# the pinned channels catch up with the Rider release.
jetbrains.rider.overrideAttrs (previous: {
  version = "2026.3";
  passthru = previous.passthru // {
    buildNumber = "263.7307.258";
  };
  src = fetchurl {
    url = "https://download.jetbrains.com/rider/JetBrains.Rider-2026.3.tar.gz";
    hash = "sha256-Hvx0/9CuHt8UN7NWKezwhi65dGQwxDE+bu9AhXUWXCE=";
  };
  buildInputs = previous.buildInputs ++ [
    curl
    libsecret
    libsoup_3
    webkitgtk_4_1
  ];
  # MSAL uses the shared WebKit API and only soup_message_headers_append from
  # libsoup. Those calls retain their signatures with WebKit 4.1 / libsoup 3.
  postPatch = previous.postPatch + ''
    for library in lib/ReSharperHost/{linux-x64,runtimes/linux-x64/native}/libmsalruntime.so; do
      patchelf \
        --replace-needed libwebkit2gtk-4.0.so.37 libwebkit2gtk-4.1.so.0 \
        --replace-needed libjavascriptcoregtk-4.0.so.18 libjavascriptcoregtk-4.1.so.0 \
        --replace-needed libsoup-2.4.so.1 libsoup-3.0.so.0 \
        "$library"
    done
  '';
  # The Android debugger agent runs on the target device, which supplies liblog.
  autoPatchelfIgnoreMissingDeps = (previous.autoPatchelfIgnoreMissingDeps or [ ]) ++ [ "liblog.so" ];
})
