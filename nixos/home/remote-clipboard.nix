{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  clipboardWrapper =
    name:
    lib.hiPrio (
      pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.systemd
        ];
        text = ''
          exec ${pkgs.bash}/bin/bash ${./wayland-clipboard.sh} ${pkgs.wl-clipboard}/bin/${name} "$@"
        '';
      }
    );
in
{
  home.packages = [
    # Keep standard command names available to clipboard-detecting apps.
    (clipboardWrapper "wl-copy")
    (clipboardWrapper "wl-paste")
    (pkgs.writeShellApplication {
      name = "remote-clip";
      runtimeInputs = [
        pkgs.openssh
        osConfig.services.tailscale.package
        pkgs.wl-clipboard
        pkgs.systemd
      ];
      text = ''
        exec ${pkgs.python3}/bin/python3 ${../assets/scripts/remote-clip.py} "$@"
      '';
    })
  ];
}
