{ pkgs, configurations }:
let
  libraries =
    host:
    pkgs.lib.findFirst (p: p.name == "ld-library-path")
      (throw "${host}: nix-ld library environment missing")
      configurations.${host}.config.environment.systemPackages;
in
pkgs.runCommand "t3-browser-libraries" { } ''
  for hostLibraries in ${libraries "rocket"} ${libraries "framework"}; do
    for library in \
      libglib-2.0.so.0 libgobject-2.0.so.0 libgio-2.0.so.0 \
      libnspr4.so libnss3.so libnssutil3.so \
      libatk-1.0.so.0 libatk-bridge-2.0.so.0 libatspi.so.0 \
      libdbus-1.so.3 libX11.so.6 libXcomposite.so.1 libXdamage.so.1 \
      libXext.so.6 libXfixes.so.3 libXrandr.so.2 libgbm.so.1 \
      libexpat.so.1 libxcb.so.1 libxkbcommon.so.0 libudev.so.1 libasound.so.2; do
      test -e "$hostLibraries/share/nix-ld/lib/$library" || {
        echo "Missing T3 browser dependency: $hostLibraries/$library" >&2
        exit 1
      }
    done
  done
  touch "$out"
''
