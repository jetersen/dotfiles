# Home DNS over LAN/Tailscale, with public DoH only during a home DNS outage.
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  source = ../../home/dot_local/share/homelab-dns;
  python = pkgs.python3.withPackages (ps: [ ps.dbus-python ]);
in
{
  # Stable's 2.0.7 is affected by CVE-2026-52682; the locked unstable
  # package includes the fix without changing the system's base package set.
  nixpkgs.overlays = [
    (_: prev: {
      dnsdist = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system}.dnsdist;
    })
  ];
  services.resolved.enable = lib.mkForce false;
  networking.networkmanager.dns = lib.mkForce "none";
  networking.resolvconf.enable = false;
  environment.etc."resolv.conf".text = ''
    nameserver 127.0.0.2
    search rockhopper-bleak.ts.net
    options timeout:2 attempts:2
  '';
  services.tailscale.extraSetFlags = [ "--accept-dns=false" ];
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
  };

  services.dnsdist = {
    enable = true;
    listenAddress = "127.0.0.2";
    extraConfig = builtins.replaceStrings [ ''setLocal("127.0.0.2:53")'' ] [ "" ] (
      builtins.readFile (source + "/dnsdist.conf")
    );
  };
  systemd.services.dnsdist = {
    requires = [ "homelab-dns-vpn.service" ];
    after = [ "homelab-dns-vpn.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 2;
      # dnsdist binds its VPN backend sockets to their originating tunnel.
      AmbientCapabilities = [
        "CAP_NET_BIND_SERVICE"
        "CAP_NET_RAW"
      ];
      CapabilityBoundingSet = [
        "CAP_NET_BIND_SERVICE"
        "CAP_NET_RAW"
      ];
    };
  };

  environment.etc."homelab-dns/config.json".text = builtins.toJSON {
    mode = "dnsdist";
    uid = config.users.users.joseph.uid;
    domains_file = config.sops.secrets.vpn-domains.path;
  };
  # OpenVPN retains resolver metadata without writing the system's resolv.conf.
  programs.openvpn3.netcfg.settings = {
    systemd_resolved = false;
    resolv_conf_file = "/var/lib/openvpn3/dnsdist-resolv.conf";
  };
  # OpenVPN treats these backends as mutually exclusive even when the JSON
  # boolean is false. The upstream NixOS module always emits that boolean.
  environment.etc."openvpn3/netcfg.json".source = lib.mkForce (
    (pkgs.formats.json { }).generate "netcfg.json" (
      builtins.removeAttrs config.programs.openvpn3.netcfg.settings [ "systemd_resolved" ]
    )
  );
  systemd.tmpfiles.rules = [
    "d /var/lib/openvpn3 0750 openvpn openvpn -"
    "f /var/lib/openvpn3/dnsdist-resolv.conf 0640 openvpn openvpn - nameserver\\x20127.0.0.2"
  ];
  systemd.services.homelab-dns-vpn = {
    description = "Publish validated OpenVPN split DNS to dnsdist";
    wantedBy = [ "multi-user.target" ];
    after = [ "dbus.service" ];
    before = [ "dnsdist.service" ];
    wants = [ "dnsdist.service" ];
    restartTriggers = [ config.sops.secrets.vpn-domains.sopsFile ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${python}/bin/python3 ${source}/vpn_bridge.py";
      Restart = "always";
      RestartSec = 2;
      StateDirectory = "homelab-dns";
      StateDirectoryMode = "0750";
      Group = "dnsdist";
      UMask = "0027";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      PrivateTmp = true;
      ReadWritePaths = [ "/var/lib/homelab-dns" ];
    };
  };
  home-manager.users.joseph.xdg.configFile."dms-openvpn3/dns.json".text = lib.mkForce (
    builtins.toJSON {
      backend = "dnsdist";
      profiles = lib.genAttrs [ "moviestarplanet" "moviestarplanet-tcp" ] (_: {
        enabled = true;
        file = "${config.home-manager.users.joseph.xdg.configHome}/dms-openvpn3/application-domains.json";
      });
    }
  );
}
