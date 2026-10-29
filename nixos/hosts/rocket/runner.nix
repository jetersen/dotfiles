{ config, pkgs, ... }:
let
  composeDirectory = "/home/joseph/git/homelab/infrastructure/forgejo/runner";
  registrationDirectory = "/home/joseph/.local/state/forgejo-runner/registration";
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name homelab-forgejo-runner --file ${composeDirectory}/compose.yaml";
  waitForCache = pkgs.writeShellScript "wait-for-runner-cache-dns" ''
    until ${pkgs.getent}/bin/getent ahostsv4 truenas.lan.jetersen.dev >/dev/null; do
      ${pkgs.coreutils}/bin/sleep 3
    done
  '';
in
{
  # The homelab repository owns the pinned images, runner labels and Compose topology.
  # Restore its two named data volumes and registration before creating this marker.
  systemd.services.forgejo-runner = {
    description = "Homelab Forgejo runner";
    # A timer starts the container health check without blocking desktop boot.
    restartIfChanged = false;
    requires = [ "docker.service" ];
    # Docker upgrades stop dependent services; pull the runner back into startup
    # and propagate explicit Docker restarts without restarting it for unit edits.
    wantedBy = [ "docker.service" ];
    partOf = [ "docker.service" ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "docker.service"
      "network-online.target"
      "tailscaled.service"
    ];
    unitConfig.ConditionPathExists = [
      "${composeDirectory}/compose.yaml"
      "${registrationDirectory}/uuid"
      "${registrationDirectory}/token"
      "/var/lib/forgejo-runner/migration-ready"
    ];
    environment.RUNNER_REGISTRATION_DIR = registrationDirectory;
    path = [ config.virtualisation.docker.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = composeDirectory;
      # network-online.target has no waiter on this desktop. Wait only here,
      # before Docker tries resolving the NFS volume through the LAN resolver.
      ExecStartPre = "${pkgs.coreutils}/bin/timeout 120 ${waitForCache}";
      ExecStart = "${compose} up --detach --wait --no-build";
      ExecStop = "${compose} stop";
      TimeoutStartSec = 420;
      TimeoutStopSec = 660;
      UMask = "0077";
      Restart = "on-failure";
      RestartSec = 15;
    };
  };
  systemd.timers.forgejo-runner = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      Unit = "forgejo-runner.service";
    };
  };
}
