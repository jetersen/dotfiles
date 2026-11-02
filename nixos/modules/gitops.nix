{
  config,
  inputs,
  pkgs,
  ...
}:
let
  pc2mqtt = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.pc2mqtt;
  startUpgrade = "${pkgs.systemd}/bin/systemctl --no-block start nixos-upgrade.service";
in
{
  # A running Comin evaluates this attribute in the target flake before it can
  # deploy the configuration that retires it. Preserve the old nullable default.
  imports = [
    (
      { lib, ... }:
      {
        options.services.comin.machineId = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          internal = true;
          description = "Machine identity compatibility for retiring Comin installations.";
        };
      }
    )
  ];

  sops.secrets.nix-cache-netrc = {
    owner = "joseph";
    mode = "0600";
  };

  nix.settings = {
    substituters = [ "https://nix-cache.jetersen.dev/workstations" ];
    trusted-public-keys = [ "workstations:DVP/4iu54FicWbjvEU44a+Y7izu351Ty7+fbvaiNFas=" ];
    netrc-file = config.sops.secrets.nix-cache-netrc.path;
    narinfo-cache-negative-ttl = 0;
  };

  system.autoUpgrade = {
    enable = true;
    flake = "git+https://forgejo.jetersen.dev/jetersen/dotfiles.git?ref=main#${config.networking.hostName}";
    upgrade = false;
    flags = [ "--no-write-lock-file" ];
    operation = "switch";
    allowReboot = false;
    dates = "daily";
    persistent = true;
  };

  systemd.services.nixos-upgrade = {
    wantedBy = [ "multi-user.target" ];
    environment.NIX_CONFIG = ''
      always-allow-substitutes = true
      max-jobs = 1
      cores = 4
      fallback = false
    '';
    serviceConfig = {
      StateDirectory = "pc2mqtt";
      StateDirectoryMode = "0700";
      TimeoutStartSec = "6h";
      # Let an existing Comin deployment finish before this updater takes over.
      ExecCondition = "${pkgs.bash}/bin/bash -c '! ${pkgs.systemd}/bin/systemctl --quiet is-active comin.service'";
      ExecStopPost = "${pc2mqtt}/bin/pc2mqtt --report-update-result";
    };
  };

  # An inert compatibility unit lets Comin finish the activation which retires
  # it. Its existing changed-unit handling then exits without being restarted.
  systemd.services.comin = {
    restartIfChanged = false;
    unitConfig.X-StopOnRemoval = false;
    unitConfig.OnSuccess = "nixos-upgrade.service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/true";
      Restart = "no";
    };
  };

  # Stop the old session listener too; it otherwise reconnects to the retired API.
  systemd.services.retire-comin-desktop = {
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/run/user/${toString config.users.users.joseph.uid}/bus";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "-${pkgs.systemd}/bin/systemctl --user --machine=joseph@.host --no-block stop comin-desktop.service";
    };
  };

  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "nixos-network-upgrade" ''
        case "$2" in
          up|vpn-up|vpn-down|dhcp4-change|dhcp6-change|connectivity-change)
            ${startUpgrade}
            ;;
        esac
      '';
    }
  ];
  powerManagement.resumeCommands = startUpgrade;
}
