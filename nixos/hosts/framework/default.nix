{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports =
    lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix
    ++ lib.optional (builtins.pathExists ./disk.nix) ./disk.nix;

  assertions = [
    {
      assertion = builtins.pathExists ./hardware-configuration.nix;
      message = "Generate nixos/hosts/framework/hardware-configuration.nix from the Framework live environment before installing.";
    }
  ];

  networking.hostName = "framework";
  boot.kernelPackages = pkgs.linuxPackages_latest;
  dotfiles.storage.swapSize = "72G";

  sops.defaultSopsFile = ../../secrets/framework.yaml;
  sops.secrets.joseph-password.neededForUsers = true;
  users.users.joseph.hashedPasswordFile = config.sops.secrets.joseph-password.path;
  users.mutableUsers = false;

  system.stateVersion = "26.05";
}
