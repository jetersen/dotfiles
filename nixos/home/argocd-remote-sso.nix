{ pkgs, osConfig, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "argocd-remote-sso";
      runtimeInputs = [
        pkgs.openssh
        osConfig.services.tailscale.package
        pkgs.openvpn3
        pkgs.yq-go
      ];
      text = ''
        exec ${pkgs.python3}/bin/python3 ${../../home/dot_local/bin/executable_argocd-remote-sso} "$@"
      '';
    })
  ];
}
