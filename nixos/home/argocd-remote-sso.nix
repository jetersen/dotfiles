{ pkgs, osConfig, ... }:
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "argocd-remote-sso";
      runtimeInputs = [
        pkgs.openssh
        osConfig.services.tailscale.package
        pkgs.yq-go
      ];
      text = ''
        exec ${pkgs.python3}/bin/python3 ${../assets/scripts/argocd-remote-sso.py} "$@"
      '';
    })
  ];
}
