{ pkgs, ... }:
{
  programs = {
    gamemode.enable = true;
    gamescope.enable = true;
    steam = {
      enable = true;
      gamescopeSession.enable = true;
      remotePlay.openFirewall = true;
      dedicatedServer.openFirewall = false;
      localNetworkGameTransfers.openFirewall = true;
    };
  };

  environment.systemPackages = with pkgs; [
    mangohud
    protonup-qt
  ];
}
