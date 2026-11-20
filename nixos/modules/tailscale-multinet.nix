# One daemon owns both tailnets and their DNS. NetworkManager supplies ordinary
# DHCP DNS while it is stopped; captive portal detection belongs to Tailscale.
{ lib, pkgs, ... }:
let
  package = pkgs.callPackage ../packages/tailscale-multinet.nix { };
  upgradeMarker = "/run/tailscale-multinet-upgrade";
in
{
  # The pinned experimental build supports the direct DNS manager, but cannot
  # capture base DNS through systemd-resolved. NM still updates its live file
  # with dns=none; this link avoids competing writes to Tailscale's resolv.conf.
  services.resolved.enable = lib.mkForce false;
  networking.networkmanager.dns = lib.mkForce "none";
  networking.resolvconf.enable = false;
  environment.etc."resolv.conf".source = "/run/NetworkManager/no-stub-resolv.conf";
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
    after = [ "NetworkManager-wait-online.service" ];
    wants = [ "NetworkManager-wait-online.service" ];
    environment = {
      TS_NO_LOGS_NO_SUPPORT = "true";
      TS_DISABLE_UPNP = "true";
    };
    path = [
      pkgs.iproute2
      pkgs.iptables
      pkgs.kmod
    ];
    # Keep the existing authenticated state and saved explicit attachment set.
    serviceConfig = {
      ExecStart = "${package}/bin/tailscaled --experimental-multi-profile --encrypt-state=false --state=/var/lib/tailscale-multi-profile-test/tailscaled.state --statedir=/var/lib/tailscale-multi-profile-test --socket=/run/tailscale/tailscaled.sock --tun=tailscale-mp --port=41641";
      StateDirectory = "tailscale-multi-profile-test";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "tailscale";
      RuntimeDirectoryMode = "0755";
      # This experimental pin has no supported hard-crash repair path.
      Restart = "no";
      TimeoutStopSec = "60s";
    };
  };

  # Let Tailscale restore ordinary DNS before activation replaces /etc. Run only
  # for a different cached system; same-revision notifications leave it alone.
  dotfiles.gitops.prepareSwitch = pkgs.writeShellApplication {
    name = "tailscale-prepare-upgrade";
    runtimeInputs = [
      pkgs.systemd
      pkgs.coreutils
    ];
    text = ''
      if systemctl --quiet is-active tailscale-multi-profile.service; then
        touch ${upgradeMarker}
        systemctl stop tailscale-multi-profile.service
      fi
    '';
  };
  systemd.services.nixos-upgrade.serviceConfig.ExecStopPost = lib.mkAfter [
    (lib.getExe (
      pkgs.writeShellApplication {
        name = "tailscale-finish-upgrade";
        runtimeInputs = [
          pkgs.systemd
          pkgs.coreutils
        ];
        text = ''
          if [[ -e ${upgradeMarker} ]]; then
            rm ${upgradeMarker}
            systemctl --no-block start tailscale-multi-profile.service
          fi
        '';
      }
    ))
  ];
}
