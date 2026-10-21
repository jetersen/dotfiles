{ config, lib, ... }:
{
  programs.openvpn3.enable = true;

  # Reconciliation must not depend on interactive authorization. Permit only
  # routing operations on numbered tunnels, never DNS servers or LAN links.
  security.polkit.extraConfig = lib.mkIf config.services.resolved.enable ''
    polkit.addRule(function(action, subject) {
      if (subject.user === "joseph" &&
          /^tun[0-9]+$/.test(action.lookup("interface") || "") &&
          (action.id === "org.freedesktop.resolve1.set-domains" ||
           action.id === "org.freedesktop.resolve1.set-default-route")) {
        return polkit.Result.YES;
      }
    });
  '';

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
