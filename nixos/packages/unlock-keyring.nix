{ python3, writeShellApplication }:
let
  python = python3.withPackages (ps: [ ps.dbus-python ]);
in
writeShellApplication {
  name = "unlock-keyring";
  text = ''
    exec ${python}/bin/python3 ${../../home/dot_local/bin/executable_unlock-keyring} "$@"
  '';
}
