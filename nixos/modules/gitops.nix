{
  config,
  lib,
  pkgs,
  ...
}:
let
  fetch = pkgs.writeShellScript "comin-fetch" (
    lib.replaceStrings
      [ "@systemctl@" "@timeout@" "@comin@" "@jq@" "@sleep@" ]
      [
        "${pkgs.systemd}/bin/systemctl"
        "${pkgs.coreutils}/bin/timeout"
        (lib.getExe config.services.comin.package)
        (lib.getExe pkgs.jq)
        "${pkgs.coreutils}/bin/sleep"
      ]
      (builtins.readFile ../gitops/fetch.sh)
  );
  startFetchCommand = "${pkgs.systemd}/bin/systemctl start comin-fetch.service";
  notify = pkgs.writeShellScript "comin-notify" ''
    set -euo pipefail
    if [[ "''${SSH_ORIGINAL_COMMAND:-}" != fetch && "''${SSH_ORIGINAL_COMMAND:-}" != 'comin fetch' ]]; then
      echo 'Only the fetch notification is supported.' >&2
      exit 2
    fi
    exec /run/wrappers/bin/sudo -n ${startFetchCommand}
  '';
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

    users.groups.comin-notify = { };
    users.users.comin-notify = {
      isSystemUser = true;
      group = "comin-notify";
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = [
        ''restrict,command="${notify}" ${lib.removeSuffix "\n" (builtins.readFile ../keys/deploy-notify.pub)}''
      ];
    };
    security.sudo.extraRules = [
      {
        users = [ "comin-notify" ];
        runAs = "root";
        commands = [
          {
            command = startFetchCommand;
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    systemd.services.comin-fetch = {
      description = "Check for a published NixOS deployment";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "comin.service"
      ];
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        # Each event rearms a one-shot check, even while the checker is busy.
        ExecStart = "${pkgs.systemd}/bin/systemctl --no-block restart comin-fetch-retry.timer";
        TimeoutStartSec = 120;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    # No wantedBy or repeating timer: only a notification/lifecycle event starts
    # this chain. Busy operations defer the requested fetch until they settle.
    systemd.timers.comin-fetch-retry = {
      # Network event bursts may rearm this timer many times before it expires.
      unitConfig.StartLimitIntervalSec = 0;
      timerConfig = {
        # Longer than the worker's 90s timeout: a notification arriving
        # during that worker cannot expire while its service is still active.
        OnActiveSec = "120s";
        AccuracySec = "1s";
        Unit = "comin-fetch-retry.service";
      };
    };
    systemd.services.comin-fetch-retry = {
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = fetch;
        TimeoutStartSec = 90;
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
    systemd.services.comin.environment.NIX_CONFIG = ''
      always-allow-substitutes = true
      max-jobs = 1
      cores = 4
      fallback = false
    '';
  };
}
