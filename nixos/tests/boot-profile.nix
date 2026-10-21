{ pkgs, configurations }:
let
  rocket = configurations.rocket.config;
  framework = configurations.framework.config;
  hook = framework.boot.loader.external.installHook;
  lanzaboote = framework.boot.lanzaboote.package;
in
assert rocket.boot.loader.systemd-boot.enable && !rocket.boot.loader.external.enable;
assert rocket.system.build.installBootLoader.name == "install-systemd-boot.sh";
assert framework.boot.lanzaboote.enable && !framework.boot.loader.systemd-boot.enable;
assert toString framework.system.build.installBootLoader == toString hook;
assert !framework.boot.lanzaboote.allowUnsigned;
assert framework.boot.lanzaboote.protectedSystem == "/run/booted-system";
assert lanzaboote.doCheck;
pkgs.runCommand "boot-profile-contract-checks"
  {
    nativeBuildInputs = [ pkgs.gnugrep ];
  }
  ''
    # Check the production hook and its actual CLI together. No boot partition
    # or signing keys are accessed: install --help exits without installing.
    ${pkgs.lib.getExe lanzaboote} install --help > help
    grep -q -- '--profiles-directory' help
    grep -q -- '--default-system' help
    grep -q -- '--protected-system' help
    grep -q -- '--profiles-directory=/nix/var/nix/profiles' ${hook}
    grep -q -- '--default-system=' ${hook}
    grep -q -- '--protected-system=/run/booted-system' ${hook}
    touch "$out"
  ''
