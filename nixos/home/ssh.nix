{
  config,
  lib,
  pkgs,
  ...
}:
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
      framework = {
        HostName = "framework";
        HostKeyAlias = "framework";
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

  # FHS user namespaces map the Nix store's root owner to nobody, which SSH
  # rejects for user config files. Install the generated config as the user.
  home.file.".ssh/config".enable = false;
  home.activation.configureSsh = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${pkgs.coreutils}/bin/install -d -m 700 ${lib.escapeShellArg "${config.home.homeDirectory}/.ssh"}
    run ${pkgs.coreutils}/bin/install -m 600 ${config.home.file.".ssh/config".source} \
      ${lib.escapeShellArg "${config.home.homeDirectory}/.ssh/config"}
  '';
}
