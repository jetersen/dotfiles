{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal-new-kernel.nix") ];

  networking.hostName = "framework-installer";
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  users.users.root.openssh.authorizedKeys.keyFiles = [ ./keys/joseph.pub ];

  services.avahi = {
    enable = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  image.baseName = lib.mkForce "nixos-26.05-framework-installer";
  system.stateVersion = "26.05";
}
