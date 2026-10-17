# Optional system integration for Steam, including 32-bit graphics and controllers.
{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    extraCompatPackages = [ (pkgs.callPackage ../packages/proton-ge.nix { }) ];
    protontricks.enable = true;
  };
  home-manager.users.joseph = {
    home.packages = with pkgs; [
      lutris
    ];
    xdg.configFile."niri/cfg/gaming-rules.kdl".source = ../../home/dot_config/niri/cfg/gaming-rules.kdl;
    dotfiles.niri.extraConfig = ''
      include "cfg/gaming-rules.kdl"
    '';
  };
}
