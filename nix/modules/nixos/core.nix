{
  lib,
  pkgs,
  ...
}:
{
  boot = {
    kernelPackages = pkgs.linuxPackages_7_1;
    loader = {
      systemd-boot.enable = lib.mkDefault true;
      efi.canTouchEfiVariables = lib.mkDefault true;
      timeout = 3;
    };
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      warn-dirty = false;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Copenhagen";
  i18n = {
    defaultLocale = "en_DK.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "da_DK.UTF-8";
      LC_IDENTIFICATION = "da_DK.UTF-8";
      LC_MEASUREMENT = "da_DK.UTF-8";
      LC_MONETARY = "da_DK.UTF-8";
      LC_NAME = "da_DK.UTF-8";
      LC_NUMERIC = "da_DK.UTF-8";
      LC_PAPER = "da_DK.UTF-8";
      LC_TELEPHONE = "da_DK.UTF-8";
      LC_TIME = "da_DK.UTF-8";
    };
  };

  users = {
    # Keep mutable during scaffolding so nixos-install can establish credentials.
    # Replace with declarative, encrypted credentials before unattended installs.
    mutableUsers = true;
    users.joseph = {
      isNormalUser = true;
      description = "Joseph Petersen";
      shell = pkgs.fish;
      extraGroups = [
        "docker"
        "wheel"
        "networkmanager"
      ];
    };
  };

  programs.fish.enable = true;
  security.sudo.wheelNeedsPassword = true;
  virtualisation.docker.enable = true;

  services = {
    fwupd.enable = true;
    tailscale.enable = true;
    syncthing = {
      enable = true;
      user = "joseph";
      dataDir = "/home/joseph";
      configDir = "/home/joseph/.config/syncthing";
      openDefaultPorts = true;
    };
  };

  hardware.enableRedistributableFirmware = true;
  zramSwap.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    git
    vim
    wget
  ];

  system.stateVersion = "26.05";
}
