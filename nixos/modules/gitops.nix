{
  config,
  lib,
  pkgs,
  ...
}:
let
  fetch = pkgs.writeShellScript "comin-fetch" ''
    set -euo pipefail
    # A manual stop must continue to pause automatic deployment.
    if ! ${pkgs.systemd}/bin/systemctl --quiet is-active comin.service; then
      echo 'Comin is stopped; deployment remains paused.'
      exit 0
    fi

    # The daemon creates its control socket after systemd considers it started.
    wait_for_comin() {
      for attempt in {1..15}; do
        if status=$(${pkgs.coreutils}/bin/timeout 2 ${lib.getExe config.services.comin.package} status --json 2>/dev/null); then
          return
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      echo 'Comin control socket is not ready.' >&2
      return 1
    }

    wait_for_comin
    # Comin v0.14 only evaluates changed commits. Restart an idle failed daemon
    # to retry the same revision; its resume RPC cancels asynchronous retries.
    if ${lib.getExe pkgs.jq} -e '
      .is_suspended == false and
      .fetcher.is_fetching == false and .deployer.is_deploying == false and
      .builder.is_evaluating == false and .builder.is_building == false and
      (.builder.generation.eval_status == "failed" or
       .builder.generation.build_status == "failed")
    ' <<< "$status" > /dev/null; then
      ${pkgs.systemd}/bin/systemctl try-restart comin.service
      wait_for_comin
    fi
    exec ${pkgs.coreutils}/bin/timeout 10 ${lib.getExe config.services.comin.package} fetch
  '';
  startFetchCommand = "${pkgs.systemd}/bin/systemctl start comin-fetch.service";
  notify = pkgs.writeShellScript "comin-notify" ''
    set -euo pipefail
    if [[ "''${SSH_ORIGINAL_COMMAND:-}" != fetch ]]; then
      echo 'Only the fetch notification is supported.' >&2
      exit 2
    fi
    exec /run/wrappers/bin/sudo -n ${startFetchCommand}
  '';
  startFetch = "${pkgs.systemd}/bin/systemctl --no-block start comin-fetch.service";
in
{
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
      ExecStart = fetch;
      TimeoutStartSec = 120;
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

  # Follow main on every host, but only activate systems available in the cache.
  # Interactive Nix builds remain available.
  systemd.services.comin.serviceConfig.ExecStartPost =
    "-${pkgs.systemd}/bin/systemctl --no-block start comin-fetch.service";
  systemd.services.comin.environment.NIX_CONFIG = ''
    always-allow-substitutes = true
    max-jobs = 0
    fallback = false
  '';
}
