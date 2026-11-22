{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/pc2mqtt.nix
    ../../modules/work-tailnet.nix
    ../../modules/tailscale-multinet.nix
    inputs.self.nixosModules.workstation
    inputs.self.nixosModules.gaming
    ./hardware-configuration.nix
    ./filesystems.nix
    ./desktop.nix
    ./audio.nix
    ./dictation.nix
    ./services.nix
    ./runner.nix
    ./user-services.nix
    ./metrics.nix
  ];
  home-manager.backupFileExtension = "pre-nixos";
  networking.hostName = "rocket";
  dotfiles.tailscaleMultinet.enable = true;
  # Keep the login keyring encrypted; unlock it separately after desktop login.
  services.displayManager.autoLogin = {
    enable = true;
    user = "joseph";
  };
  # This desktop stays on the homelab LAN; use its local service VIPs directly.
  services.tailscale.extraSetFlags = lib.mkForce [
    "--accept-routes=false"
    "--ssh=true"
    # Let the user manage Tailscale Serve for the T3 server.
    "--operator=joseph"
  ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
  };
  boot.loader.efi.canTouchEfiVariables = true;
  # Hide the menu; hold Space at startup to select an older NixOS generation.
  boot.loader.timeout = 0;

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

  system.stateVersion = "26.05";
}
