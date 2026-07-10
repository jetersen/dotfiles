{
  lib,
  pkgs,
  ...
}:
{
  boot.loader.timeout = 1;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--filter=until=720h" ];
    };
  };

  users.users.joseph.linger = true;

  environment.systemPackages = with pkgs; [
    docker-compose
    nvtopPackages.full
  ];

  services.xserver.enable = lib.mkForce false;
}
