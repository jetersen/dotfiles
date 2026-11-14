{
  config,
  lib,
  pkgs,
  ...
}:
let
  layoutWatcher = pkgs.writeShellApplication {
    name = "espanso-niri-layout";
    runtimeInputs = [
      pkgs.python3
      pkgs.systemd
    ];
    text = ''
      exec python3 ${../home/espanso-layout.py} ${../../home/dot_config/niri/cfg/input.kdl}
    '';
  };
in
{
  services.espanso = {
    enable = true;
    package = pkgs.espanso-wayland;
  };
  systemd.user.services.espanso-layout = {
    description = "Synchronize Espanso with niri's active keyboard layout";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      ExecStart = lib.getExe layoutWatcher;
      Restart = "on-failure";
    };
  };
  systemd.user.services.espanso = {
    requires = [ "espanso-layout.service" ];
    after = [ "espanso-layout.service" ];
    partOf = [ "graphical-session.target" ];
    environment.ESPANSO_CONFIG_DIR = "%t/espanso-niri";
    path = [
      config.programs.niri.package
      pkgs.coreutils
    ];
  };
}
