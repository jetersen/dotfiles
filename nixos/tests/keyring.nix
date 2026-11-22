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
    mkdir -p source/nixos/assets/scripts source/tests
    cp ${../assets/scripts/unlock-keyring.py} source/nixos/assets/scripts/unlock-keyring.py
    cp ${../../tests/test_keyring_unlock.py} source/tests/test_keyring_unlock.py
    cd source
    python3 tests/test_keyring_unlock.py -v
    touch "$out"
  ''
