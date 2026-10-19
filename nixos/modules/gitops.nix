{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  pc2mqtt = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pc2mqtt;
  startFetch = "${pkgs.systemd}/bin/systemctl --no-block start comin-fetch.service";
in
{
  config = {
    sops.secrets.nix-cache-netrc = {
      owner = "joseph";
      mode = "0600";
    };

    nix.settings = {
      substituters = [ "https://nix-cache.jetersen.dev/workstations" ];
      trusted-public-keys = [ "workstations:DVP/4iu54FicWbjvEU44a+Y7izu351Ty7+fbvaiNFas=" ];
      netrc-file = config.sops.secrets.nix-cache-netrc.path;
      # A lifecycle check can precede CI's upload. Retry new cache paths immediately.
      narinfo-cache-negative-ttl = 0;
    };

    services.comin = {
      enable = true;
      package = inputs.comin.packages.${pkgs.stdenv.hostPlatform.system}.comin;
      desktop.enable = true;
      remotes = [
        {
          name = "forgejo";
          url = "https://forgejo.jetersen.dev/jetersen/dotfiles.git";
          branches.main.name = "main";
          branches.testing.name = "";
          # CI and local lifecycle events request fetches through the control socket.
          poller.period = 0;
        }
      ];
      exporter.listen_address = "127.0.0.1";
    };

    systemd.user.services.comin-desktop = {
      after = [ "dms.service" ];
      partOf = [ "graphical-session.target" ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        ExecStart = lib.mkForce ''${lib.getExe config.services.comin.package} desktop --title "System update" --reboot-only'';
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Socket creation/replacement wakes pending requests without reconnect polling.
    systemd.paths.comin-fetch = {
      description = "Watch for Comin control socket changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = "/var/lib/comin/grpc.sock";
        Unit = "comin-fetch.service";
      };
    };

    systemd.services.comin-fetch = {
      description = "Check for a published NixOS deployment";
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "pc2mqtt.service"
      ];
      unitConfig.ConditionPathIsSocket = "/run/pc2mqtt/update.sock";
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pc2mqtt}/bin/pc2mqtt --request-update";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    networking.networkmanager.dispatcherScripts = [
      {
        source = pkgs.writeShellScript "comin-network-fetch" ''
          case "$2" in
            up|vpn-up|vpn-down|dhcp4-change|dhcp6-change|connectivity-change)
              ${startFetch}
              ;;
          esac
        '';
      }
    ];
    powerManagement.resumeCommands = startFetch;

    # Prefer CI outputs while allowing large packages excluded from Attic.
    systemd.services.comin.environment = {
      COMIN_ALLOW_REWRITTEN_MAIN = "1";
      NIX_CONFIG = ''
        always-allow-substitutes = true
        max-jobs = 1
        cores = 4
        fallback = false
      '';
    };
  };
}
