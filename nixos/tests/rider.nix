{ pkgs, configurations }:
let
  riderFor =
    host:
    builtins.head (
      builtins.filter (
        p: (p.pname or "") == "rider"
      ) configurations.${host}.config.home-manager.users.joseph.home.packages
    );
  rider = riderFor "rocket";
in
assert rider.version == "2026.3";
assert rider.buildNumber == "263.7307.258";
assert (riderFor "framework").drvPath == rider.drvPath;
pkgs.runCommand "rider-smoke" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  test -x ${rider}/bin/rider
  test -f ${rider}/share/applications/rider.desktop
  python3 - <<'PY'
  import ctypes
  import json
  import os
  from pathlib import Path

  root = Path("${rider}/rider")
  product = json.loads((root / "product-info.json").read_text())
  assert product["version"] == "${rider.version}"
  assert product["buildNumber"] == "${rider.buildNumber}"
  # Resolve all imports now, including the WebKit/libsoup compatibility fix.
  for relative in ("linux-x64", "runtimes/linux-x64/native"):
      ctypes.CDLL(str(root / "lib/ReSharperHost" / relative / "libmsalruntime.so"), mode=os.RTLD_NOW)
  PY
  ${rider}/rider/lib/ReSharperHost/linux-x64/dotnet/dotnet --list-runtimes > runtimes
  grep '^Microsoft.NETCore.App 10\.' runtimes
  touch "$out"
''
