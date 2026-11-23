# One daemon owns both tailnets and their DNS. NetworkManager supplies ordinary
# DHCP DNS while it is stopped; captive portal detection belongs to Tailscale.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.tailscaleMultinet;
  package = pkgs.callPackage ../packages/tailscale-multinet.nix { };
  statePath = "/var/lib/${cfg.stateDirectory}";
  stateFile = "${statePath}/tailscaled.state";
in
{
  options.dotfiles.tailscaleMultinet = {
    enable = lib.mkEnableOption "the shared experimental simultaneous-tailnet daemon";
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "[a-zA-Z0-9][a-zA-Z0-9_.-]*";
      default = "tailscale-multi-profile";
      description = "Private state directory under /var/lib, provisioned before activation.";
    };
    interfaceName = lib.mkOption {
      type = lib.types.strMatching "[a-zA-Z0-9][a-zA-Z0-9_-]{0,14}";
      default = "tailscale0";
      description = "Primary tunnel interface; retain the host's existing firewall interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.dotfiles.workTailnet.enable;
        message = "The shared multinet daemon cannot run alongside the legacy work namespace.";
      }
    ];
    # Resolved owns resolv.conf; NetworkManager supplies underlay DNS and the
    # shared daemon supplies tailnet DNS through resolved's per-link API.
    services.resolved.enable = lib.mkForce true;
    networking.networkmanager.dns = lib.mkForce "systemd-resolved";
    networking.networkmanager.settings.connectivity.enabled = false;

    services.tailscale = {
      enable = lib.mkForce false;
      package = lib.mkForce package;
    };
    networking.firewall.allowedUDPPorts = [ 41641 ];
    environment.systemPackages = [ package ];
    home-manager.users.joseph.home.file.".local/bin/tailscale-experimental" = {
      source = "${package}/bin/tailscale";
      force = true;
    };
    systemd.services.tailscale-multi-profile = {
      description = "Experimental simultaneous Tailscale profiles";
      wantedBy = [ "multi-user.target" ];
      aliases = [ "tailscaled.service" ];
      conflicts = [ "tailscaled-work.service" ];
      after = [
        "systemd-resolved.service"
        "NetworkManager-wait-online.service"
        "tailscaled-work.service"
      ];
      wants = [
        "systemd-resolved.service"
        "NetworkManager-wait-online.service"
      ];
      environment = {
        TS_NO_LOGS_NO_SUPPORT = "true";
        TS_DISABLE_UPNP = "true";
      };
      path = [
        pkgs.iproute2
        pkgs.iptables
        pkgs.kmod
        pkgs.getent
      ];
      # Keep the existing authenticated state and saved explicit attachment set.
      serviceConfig = {
        # Require an explicit state handoff; no enrollment is configured here.
        ExecStartPre = "${pkgs.coreutils}/bin/test -s ${stateFile}";
        ExecStart = "${package}/bin/tailscaled --experimental-multi-profile --encrypt-state=false --state=${stateFile} --statedir=${statePath} --socket=/run/tailscale/tailscaled.sock --tun=${cfg.interfaceName} --port=41641";
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        RuntimeDirectory = "tailscale";
        RuntimeDirectoryMode = "0755";
        # Keep restarts explicit for the experimental deployment.
        Restart = "no";
        TimeoutStopSec = "60s";
      };
    };
  };
}
