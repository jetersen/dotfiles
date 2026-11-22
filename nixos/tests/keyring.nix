{ pkgs }:
pkgs.runCommand "keyring-unlock-checks"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (ps: [ ps.dbus-python ]))
      pkgs.dbus
      pkgs.gnome-keyring
    ];
  }
  ''
    mkdir -p source/home/dot_local/bin source/tests
    cp ${../../home/dot_local/bin/executable_unlock-keyring} source/home/dot_local/bin/executable_unlock-keyring
    cp ${../../tests/test_keyring_unlock.py} source/tests/test_keyring_unlock.py
    cd source
    python3 tests/test_keyring_unlock.py -v
    touch "$out"
  ''
