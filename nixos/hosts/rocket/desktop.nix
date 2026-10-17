# Import into Rocket's host once its hardware and installation layout are ready.
{ pkgs, ... }:
{
  services.input-remapper = {
    enable = true;
    # Keep remapping opt-in, matching the current disabled service and empty autoload list.
    serviceWantedBy = [ ];
  };

  # Slack is also used on the personal desktop, without company access setup.
  home-manager.users.joseph.home.packages = [ pkgs.slack ];

  # Reuse the installed game on the games SSD inside Steam's Linux runtime.
  home-manager.users.joseph.xdg.desktopEntries.warthunder-launcher = {
    name = "War Thunder";
    exec = "${pkgs.steam-run}/bin/steam-run /media/games/WarThunder/launcher";
    terminal = false;
    categories = [ "Game" ];
    settings = {
      Path = "/media/games/WarThunder";
      StartupWMClass = "War Thunder (Vulkan, 64bit)";
    };
  };

  home-manager.users.joseph.dotfiles.niri = {
    workspaceOutputs.music = "Lenovo Group Limited LEN P27h-10 0x344D3533";
    extraConfig = ''
      window-rule {
        match app-id="sc2_x64.exe"
        open-on-output "DP-1"
      }
    '';
  };
}
