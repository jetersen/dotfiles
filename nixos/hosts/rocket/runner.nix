{ config, pkgs, ... }:
let
  composeDirectory = "/home/joseph/git/homelab/infrastructure/forgejo/runner";
  registrationDirectory = "/home/joseph/.local/state/forgejo-runner/registration";
  compose = "${pkgs.docker-compose}/bin/docker-compose --project-name homelab-forgejo-runner --file ${composeDirectory}/compose.yaml";
in
{
  # The homelab repository owns the pinned images, runner labels and Compose topology.
  # Restore its two named data volumes and registration before creating this marker.
  systemd.services.forgejo-runner = {
    description = "Homelab Forgejo runner";
    # A timer starts the container health check without blocking desktop boot.
    restartIfChanged = false;
    requires = [ "docker.service" ];
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
      ExecStart = "${compose} up --detach --wait --no-build";
      ExecStop = "${compose} stop";
      TimeoutStartSec = 300;
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
