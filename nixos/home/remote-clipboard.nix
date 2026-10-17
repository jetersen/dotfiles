{ pkgs, osConfig, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "remote-clip";
      runtimeInputs = [
        pkgs.openssh
        osConfig.services.tailscale.package
        pkgs.wl-clipboard
        pkgs.systemd
      ];
      text = ''
        exec ${pkgs.python3}/bin/python3 ${../../home/dot_local/bin/executable_remote-clip} "$@"
      '';
    })
  ];
}
