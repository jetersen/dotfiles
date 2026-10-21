{ pkgs, configurations }:
let
  fixtures = map (
    n:
    pkgs.runCommand "boot-profile-fixture-${toString n}" { } ''
      mkdir "$out"
      echo '{}' > "$out/boot.json"
    ''
  ) (pkgs.lib.range 0 3);
  sources = pkgs.linkFarm "boot-profile-test-sources" [
    {
      name = "tests/test_standard_boot_profile.py";
      path = ../../tests/test_standard_boot_profile.py;
    }
    {
      name = "nixos/modules/standard-boot-profile.py";
      path = ../modules/standard-boot-profile.py;
    }
  ];
  hosts = map (host: configurations.${host}.config) [
    "rocket"
    "framework"
  ];
in
assert pkgs.lib.all (
  c: c.system.build.installBootLoader.name == "install-bootloader-with-system-profile"
) hosts;
assert (builtins.elemAt hosts 0).boot.loader.systemd-boot.enable;
assert (builtins.elemAt hosts 1).boot.lanzaboote.enable;
assert !(builtins.elemAt hosts 1).boot.lanzaboote.allowUnsigned;
pkgs.runCommand "boot-profile-checks"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    BOOT_TEST_NIX_ENV = "${pkgs.nix}/bin/nix-env";
    BOOT_TEST_PYTHON = "${pkgs.python3}/bin/python3";
    BOOT_TEST_SYSTEM_0 = builtins.elemAt fixtures 0;
    BOOT_TEST_SYSTEM_1 = builtins.elemAt fixtures 1;
    BOOT_TEST_SYSTEM_2 = builtins.elemAt fixtures 2;
    BOOT_TEST_SYSTEM_3 = builtins.elemAt fixtures 3;
  }
  ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export NIX_REMOTE=local
    export NIX_STATE_DIR="$TMPDIR/nix-state"
    export NIX_LOG_DIR="$TMPDIR/nix-log"
    export NIX_CONFIG='substituters ='
    ${pkgs.nix}/bin/nix-store --load-db < ${(pkgs.closureInfo { rootPaths = fixtures; })}/registration
    python3 ${sources}/tests/test_standard_boot_profile.py -v
    touch "$out"
  ''
