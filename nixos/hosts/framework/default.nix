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
    inputs.self.nixosModules.workstation
    inputs.self.nixosModules.work
    inputs.self.nixosModules.encrypted-laptop
    inputs.self.nixosModules.secure-boot
    inputs.nixos-hardware.nixosModules.framework-intel-core-ultra-series3
    ./hardware-configuration.nix
    ../../modules/roaming-dns.nix
    ./disk.nix
  ];

  programs.dms-shell.package = pkgs.callPackage ../../packages/dms-screen-idle.nix {
    dms = inputs.dms.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  networking.hostName = "framework";
  users.users.joseph.uid = 1000;
  # Authenticate relay connections through the existing tailnet SSH policy.
  services.tailscale.extraSetFlags = [
    "--ssh=true"
    # Let the desktop app manage its Tailscale Serve HTTPS endpoint.
    "--operator=joseph"
  ];
  # Ethernet and Wi-Fi can share a subnet while Ethernet remains preferred.
  networking.firewall.checkReversePath = "loose";
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.arp_ignore" = 1;
    "net.ipv4.conf.all.arp_announce" = 2;
  };
  boot.kernelPackages = pkgs.linuxPackages_latest;
  dotfiles.storage.swapSize = "72G";

  # Keep handling the closed laptop from waking it through its touch inputs.
  services.udev.extraRules = ''
    ACTION=="add|bind|change", SUBSYSTEM=="i2c", KERNEL=="i2c-CSW1322:*", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"
    ACTION=="add|bind|change", SUBSYSTEM=="i2c", KERNEL=="i2c-PIXA3854:*", TEST=="power/wakeup", ATTR{power/wakeup}="disabled"
  '';
  # Apply to already-bound devices during a configuration switch, too.
  systemd.tmpfiles.rules = [
    "w /sys/bus/i2c/devices/i2c-CSW1322:*/power/wakeup - - - - disabled"
    "w /sys/bus/i2c/devices/i2c-PIXA3854:*/power/wakeup - - - - disabled"
  ];

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
    imports = [ ./displays.nix ];
    dotfiles.prompt.showBattery = true;
    # Reuse the work dock's serial-based names, independent of connector numbering.
    dotfiles.niri.workspaceOutputs = {
      browser = "Dell Inc. DELL P2725D 24CRZ64";
      chat = "Dell Inc. DELL P2725D 24CRZ64";
      music = "Dell Inc. DELL P2725D 3S5S864";
    };
    dotfiles.niri.extraConfig = ''
      spawn-at-startup "slack" "--ozone-platform=wayland"
    '';
    xdg.configFile."niri/config.kdl".text = lib.mkBefore ''
      output "eDP-1" { scale 1.5; }
    '';
  };
  users.users.joseph.hashedPasswordFile = config.sops.secrets.joseph-password.path;
  users.mutableUsers = false;

  system.stateVersion = "26.05";
}
