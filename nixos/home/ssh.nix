{ config, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [ "local.config" ];
    settings = {
      rocket = {
        HostName = "rocket";
        HostKeyAlias = "rocket";
        User = config.home.username;
      };
      worklaptop = {
        HostName = "worklaptop";
        HostKeyAlias = "worklaptop";
        User = config.home.username;
      };
      truenasadmin = {
        HostName = "truenas";
        HostKeyAlias = "truenas";
        User = "truenas_admin";
      };
    };
  };
}
