{ ... }:
{
  programs.openvpn3.enable = true;

  # The plugin may update route-only domains on VPN links without repeated prompts.
  # DNS server addresses and physical interfaces retain the normal polkit policy.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (subject.user === "joseph" && subject.local && subject.active &&
          /^tun[0-9]+$/.test(action.lookup("interface") || "") &&
          (action.id === "org.freedesktop.resolve1.set-domains" ||
           action.id === "org.freedesktop.resolve1.set-default-route")) {
        return polkit.Result.YES;
      }
    });
  '';

  sops.secrets = builtins.listToAttrs (
    map
      (name: {
        inherit name;
        value = {
          owner = "joseph";
          group = "users";
          mode = "0600";
        };
      })
      [
        "vpn-profile"
        "vpn-profile-tcp"
        "vpn-domains"
      ]
  );

  home-manager.users.joseph.imports = [ ../home/company-vpn.nix ];
}
