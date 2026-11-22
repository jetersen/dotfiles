{ python3, writeShellApplication }:
let
  python = python3.withPackages (ps: [ ps.dbus-python ]);
in
writeShellApplication {
  name = "unlock-keyring";
  text = ''
    exec ${python}/bin/python3 ${../assets/scripts/unlock-keyring.py} "$@"
  '';
}
