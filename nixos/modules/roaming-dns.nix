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
  resolvConf = pkgs.writeText "homelab-resolv.conf" ''
    nameserver 127.0.0.2
    search rockhopper-bleak.ts.net
    options timeout:2 attempts:2
  '';
  portalPython = pkgs.python3.withPackages (ps: [
    ps.dbus-python
    ps.dnspython
  ]);
  publishResolver = pkgs.writeShellApplication {
    name = "homelab-dns-resolv";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.gawk
    ];
    text = builtins.readFile (source + "/resolv-conf.sh");
  };
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
  # NM validates the expected body/header and binds HTTP to the underlay device.
  # The probe's DNS alone always goes through the underlay bridge below.
  networking.networkmanager.settings.connectivity = {
    enabled = true;
    uri = "http://nmcheck.gnome.org/check_network_status.txt";
    response = "NetworkManager is online";
    interval = 15;
    timeout = 5;
  };
  # Add the connected work MagicDNS suffix without changing DNS servers.
  environment.etc."resolv.conf".source = "/run/homelab-dns/resolv.conf";
  services.tailscale.extraSetFlags = [ "--accept-dns=false" ];
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
  };

  services.dnsdist = {
    enable = true;
    listenAddress = "127.0.0.2";
    extraConfig = ''
      homelabDnsEndpoints = {portalLease="/run/homelab-portal/lease"}
    ''
    + builtins.replaceStrings [ ''setLocal(endpoints.listen or "127.0.0.2:53")'' ] [ "" ] (
      builtins.readFile (source + "/dnsdist.conf")
    );
  };
  systemd.services.dnsdist = {
    requires = [ "homelab-dns-resolv.service" ];
    after = [ "homelab-dns-resolv.service" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 2;
      AmbientCapabilities = [
        "CAP_NET_BIND_SERVICE"
      ];
      CapabilityBoundingSet = [
        "CAP_NET_BIND_SERVICE"
      ];
    };
  };

  systemd.services.homelab-portal-dns = {
    description = "Current-network DNS for captive portal discovery and sign-in";
    wantedBy = [ "multi-user.target" ];
    wants = [ "NetworkManager.service" ];
    after = [ "NetworkManager.service" ];
    serviceConfig = {
      ExecStart = "${portalPython}/bin/python ${./portal-dns.py}";
      Restart = "always";
      RestartSec = 1;
      RuntimeDirectory = "homelab-portal";
      RuntimeDirectoryMode = "0755";
      # SO_BINDTODEVICE prevents VPN routes from capturing underlay DNS.
      CapabilityBoundingSet = [ "CAP_NET_RAW" ];
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  systemd.services.homelab-dns-resolv = {
    description = "Publish homelab and work DNS search domains";
    wantedBy = [ "multi-user.target" ];
    before = [ "dnsdist.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe publishResolver} ${resolvConf} /run/homelab-dns/resolv.conf /run/work-tailnet/search-domain.json";
      RuntimeDirectory = "homelab-dns";
      RuntimeDirectoryMode = "0755";
      RuntimeDirectoryPreserve = "yes";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
    };
  };
  systemd.paths.homelab-dns-resolv = {
    description = "Refresh resolver search domains when work connectivity changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "/run/work-tailnet/search-domain.json";
  };
}
