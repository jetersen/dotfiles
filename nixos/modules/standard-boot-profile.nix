{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Apply to the selected installer, preserving systemd-boot's extra commands
  # and Lanzaboote's signing/measurement hooks without overriding either one.
  options.system.build.installBootLoader = lib.mkOption {
    apply =
      installer:
      if config.services.comin.enable then
        pkgs.writeShellScript "install-bootloader-with-system-profile" ''
          exec ${pkgs.python3}/bin/python3 ${./standard-boot-profile.py} \
            --nix-env ${config.nix.package}/bin/nix-env \
            --installer ${lib.escapeShellArg (toString installer)} "$@"
        ''
      else
        installer;
  };
}
