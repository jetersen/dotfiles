{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./filesystems.nix
    ./desktop.nix
    ./audio.nix
    ./services.nix
    ./runner.nix
    ./user-services.nix
  ];
  # Back up managed collisions, and retire legacy files that HM does not own.
  home-manager.backupFileExtension = "pre-nixos";
  home-manager.users.joseph = { lib, ... }: {
    home.activation.retireChezmoiStartup =
      lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
        ''
          run ${pkgs.bash}/bin/bash ${./retire-chezmoi-startup.sh} /home/joseph
        '';
  };
  networking.hostName = "rocket";
  # Keep the login keyring encrypted; unlock it separately after desktop login.
  services.displayManager.autoLogin = {
    enable = true;
    user = "joseph";
  };
  services.tailscale.extraSetFlags = [ "--ssh=true" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # Hide the menu; hold Space at startup to select NixOS or CachyOS.
  boot.loader.timeout = 0;
  # Desktop startup does not require an established network connection.
  systemd.services.NetworkManager-wait-online.enable = false;

  # Match the preserved home/data ownership rather than NixOS's default primary group.
  users.groups.joseph.gid = 1000;
  users.users.joseph = {
    uid = 1000;
    group = "joseph";
    hashedPasswordFile = config.sops.secrets.joseph-password.path;
  };
  users.mutableUsers = false;
  sops.defaultSopsFile = ../../secrets/rocket.yaml;
  sops.secrets.joseph-password.neededForUsers = true;

  # The daemon handles deployments; this desktop has no Comin status integration.
  services.comin.desktop.enable = lib.mkForce false;
  system.stateVersion = "26.05";
}
