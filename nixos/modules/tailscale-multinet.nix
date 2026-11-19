{
  config,
  lib,
  pkgs,
  ...
}:
let
  package = pkgs.callPackage ../packages/tailscale-multinet.nix { };
  marker = "/run/tailscale-multinet/owns-dns";
  native = [
    "work-tailnet-netns"
    "tailscaled"
    "tailscaled-work"
    "work-tailnet-peer-dns"
    "work-tailnet-dns"
    "work-tailnet"
    "homelab-dns-resolv"
    "homelab-portal-dns"
    "dnsdist"
    "tailscaled-set"
  ];
  control = pkgs.writeShellApplication {
    name = "tailscale-multinet";
    runtimeInputs = [
      pkgs.python3
      pkgs.systemd
      pkgs.iproute2
      pkgs.iptables
      pkgs.bind
    ];
    text = ''
      export MULTINET_PACKAGE=${package}
      exec python3 ${./tailscale-multinet/control.py} "$@"
    '';
  };
  job = action: {
    path = [ pkgs.systemd ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe control} ${action}";
      TimeoutStartSec = "8min";
      UMask = "0077";
    };
  };
in
{
  # The native DNS object is immutable and can be restored atomically. Tailscale
  # replaces the /etc link, never its store target, only while it owns DNS.
  environment.etc."resolv.conf" = {
    source = lib.mkForce (
      pkgs.writeText "framework-native-resolv.conf" ''
        nameserver 127.0.0.2
        search rockhopper-bleak.ts.net
        options timeout:2 attempts:2
      ''
    );
  };
  environment.systemPackages = [ control ];
  home-manager.users.joseph.home.file.".local/bin/tailscale-experimental" = {
    source = "${package}/bin/tailscale";
    force = true;
  };
  systemd.tmpfiles.rules = [ "d /run/tailscale-multinet 0700 root root -" ];
  systemd.services =
    (lib.genAttrs native (_: {
      unitConfig.ConditionPathExists = "!${marker}";
    }))
    // {
      tailscale-multi-profile = {
        description = "Experimental simultaneous Linux tailnets (3dc0f9b6f)";
        unitConfig = {
          ConditionPathExists = marker;
          OnFailure = "tailscale-multinet-recover.service";
        };
        environment = {
          TS_NO_LOGS_NO_SUPPORT = "true";
          TS_DISABLE_UPNP = "true";
        };
        path = [
          pkgs.iproute2
          pkgs.iptables
          pkgs.kmod
        ];
        serviceConfig = {
          ExecStart = "${package}/bin/tailscaled --experimental-multi-profile --encrypt-state=false --state=/var/lib/tailscale-multi-profile-test/tailscaled.state --statedir=/var/lib/tailscale-multi-profile-test --socket=/run/tailscale/tailscaled.sock --tun=tailscale-mp --port=41641";
          Restart = "no";
          TimeoutStopSec = "60s";
          KillMode = "control-group";
          UMask = "0077";
        };
      };
      tailscale-multinet-start = lib.recursiveUpdate (job "start") {
        unitConfig.OnFailure = "tailscale-multinet-recover.service";
      };
      tailscale-multinet-recover = lib.recursiveUpdate (job "recover") {
        unitConfig.StartLimitIntervalSec = 0;
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "20s";
        };
      };
      tailscale-multinet-portal-mode = {
        description = "Guarded native portal and simultaneous-tailnet ownership";
        wantedBy = [ "multi-user.target" ];
        after = [
          "NetworkManager.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        unitConfig.OnFailure = "tailscale-multinet-recover.service";
        serviceConfig = {
          ExecStart = "${lib.getExe control} monitor";
          Restart = "no";
        };
      };
      nixos-upgrade.serviceConfig.ExecStartPre = lib.mkBefore [
        "${pkgs.systemd}/bin/systemctl stop tailscale-multinet-portal-mode.service"
        "${pkgs.systemd}/bin/systemctl start tailscale-multinet-recover.service"
      ];
      # Re-arm monitoring even when an upgrade has no changed system to activate.
      nixos-upgrade.serviceConfig.ExecStopPost = lib.mkAfter [
        "${pkgs.systemd}/bin/systemctl --no-block start tailscale-multinet-portal-mode.service"
      ];
    };
  systemd.paths.homelab-dns-resolv.unitConfig.ConditionPathExists = "!${marker}";
  systemd.timers.tailscale-multinet-deadline.timerConfig = {
    OnActiveSec = "12min";
    Unit = "tailscale-multinet-recover.service";
  };
}
