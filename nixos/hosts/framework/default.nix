{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/containers.nix
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix
  ++ lib.optional (builtins.pathExists ./disk.nix) ./disk.nix;

  assertions = [
    {
      assertion = builtins.pathExists ./hardware-configuration.nix;
      message = "Generate nixos/hosts/framework/hardware-configuration.nix from the Framework live environment before installing.";
    }
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
  sops.secrets.aws-config = {
    owner = "joseph";
    group = "users";
    mode = "0600";
  };
  sops.secrets.kube-config = {
    owner = "joseph";
    group = "users";
    mode = "0600";
  };
  sops.secrets.ai-work-instructions = { };
  sops.secrets.npm-config = {
    owner = "joseph";
    group = "users";
    mode = "0600";
  };
  sops.secrets.varlock-work-schema = {
    owner = "joseph";
    group = "users";
    mode = "0600";
  };
  sops.templates.ai-instructions = {
    owner = "joseph";
    group = "users";
    mode = "0600";
    content =
      lib.replaceStrings [ "@AI_WORK_INSTRUCTIONS@" ] [ config.sops.placeholder.ai-work-instructions ]
        (builtins.readFile ../../../home/.chezmoitemplates/ai-instructions.md);
  };
  home-manager.users.joseph.imports = [ ../../home/cloud.nix ];
  home-manager.users.joseph.dotfiles.prompt.showBattery = true;
  users.users.joseph.hashedPasswordFile = config.sops.secrets.joseph-password.path;
  users.mutableUsers = false;

  system.stateVersion = "26.05";
}
