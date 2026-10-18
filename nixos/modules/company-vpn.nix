{ lib, ... }:
{
  programs.openvpn3.enable = true;

  sops.secrets =
    lib.genAttrs
      [
        "vpn-profile"
        "vpn-profile-tcp"
        "vpn-domains"
      ]
      (_: {
        owner = "joseph";
        group = "users";
        mode = "0600";
      });

  home-manager.users.joseph.imports = [ ../home/company-vpn.nix ];
}
