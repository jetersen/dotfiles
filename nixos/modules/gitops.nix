{
  config,
  lib,
  pkgs,
  ...
}:
let
  notify = pkgs.writeShellScript "comin-notify" ''
    set -euo pipefail
    if [[ -n "''${SSH_CONNECTION:-}" && "''${SSH_ORIGINAL_COMMAND:-}" != fetch ]]; then
      echo 'Only the fetch notification is supported.' >&2
      exit 2
    fi
    # A manual stop must continue to pause automatic deployment.
    if ! ${pkgs.systemd}/bin/systemctl --quiet is-active comin.service; then
      echo 'Comin is stopped; deployment remains paused.'
      exit 0
    fi
    # The daemon creates its socket after systemd considers it started.
    for attempt in {1..15}; do
      if [[ -S /var/lib/comin/grpc.sock ]]; then
        # A lifecycle fetch can precede CI's cache upload. Comin only notices
        # changed commits, so retry an idle failed build before fetching again.
        status=$(${pkgs.coreutils}/bin/timeout 10 ${lib.getExe config.services.comin.package} status --json)
        if ${lib.getExe pkgs.jq} -e '
          .is_suspended == false and
          .builder.is_evaluating == false and .builder.is_building == false and
          .builder.generation.eval_status == "evaluated" and
          (.builder.generation.build_err // "") != ""
        ' <<< "$status" > /dev/null; then
          ${pkgs.coreutils}/bin/timeout 10 ${lib.getExe config.services.comin.package} suspend
          ${pkgs.coreutils}/bin/timeout 10 ${lib.getExe config.services.comin.package} resume
        fi
        exec ${pkgs.coreutils}/bin/timeout 10 ${lib.getExe config.services.comin.package} fetch
      fi
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo 'Comin did not create its control socket.' >&2
    exit 1
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
      User = "comin-notify";
      ExecStart = notify;
      TimeoutStartSec = 60;
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
