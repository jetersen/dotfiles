{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./disk.nix
  ];

  networking.hostName = "framework";
  # Ethernet and Wi-Fi can share a subnet while Ethernet remains preferred.
  networking.firewall.checkReversePath = "loose";
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  dotfiles.storage.swapSize = "72G";

  # Goodix can leave fprintd with a suspended device handle mid-verification.
  # These hooks run while user.slice is frozen, before DMS can retry on resume.
  environment.etc."systemd/system-sleep/fprintd".source = pkgs.writeShellScript "fprintd-sleep" ''
    case "$1" in
      pre) ${pkgs.systemd}/bin/systemctl stop fprintd.service ;;
      post) ${pkgs.systemd}/bin/systemctl start fprintd.service ;;
    esac
  '';

  sops.defaultSopsFile = ../../secrets/framework.yaml;
  sops.secrets.joseph-password.neededForUsers = true;
  # Keep the laptop panel defaults out of the shared workstation desktop.
  environment.etc."greetd/niri_overrides.kdl".text = lib.mkAfter ''
    output "eDP-1" { scale 1.5; }
  '';
  home-manager.users.joseph = {
    dotfiles.prompt.showBattery = true;
    xdg.configFile."niri/config.kdl".text = lib.mkBefore ''
      output "eDP-1" { scale 1.5; }
    '';
  };
  users.users.joseph.hashedPasswordFile = config.sops.secrets.joseph-password.path;
  users.mutableUsers = false;

  system.stateVersion = "26.05";
}
