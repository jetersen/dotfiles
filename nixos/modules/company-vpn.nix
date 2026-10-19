{ lib, ... }:
{
  programs.openvpn3.enable = true;

  sops.secrets =
    lib.genAttrs
      [
        "vpn-profile"
        "vpn-profile-tcp"
      ]
      (_: {
        owner = "joseph";
        group = "users";
        mode = "0600";
      })
    // {
      vpn-domains = {
        sopsFile = ../secrets/vpn-domains.yaml;
        owner = "joseph";
        group = "users";
        mode = "0600";
      };
    };

  home-manager.users.joseph.imports = [ ../home/company-vpn.nix ];
}
