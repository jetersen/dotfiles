{ pkgs, ... }:
{
  imports = [
    ./ai-tools.nix
    ./desktop.nix
    ./dms.nix
    ./development.nix
    ./direnv.nix
    ./git.nix
    ./remote-clipboard.nix
    ./niri.nix
    ./media.nix
    ./shell.nix
    ./ssh.nix
    ./prompt.nix
    ./applications.nix
  ];
  home.username = "joseph";
  home.homeDirectory = "/home/joseph";
  home.stateVersion = "26.05";

  home.sessionVariables = {
    EDITOR = "zeditor --wait";
    BROWSER = "zen-browser";
  };

  home.packages = with pkgs; [
    eza
    ripgrep
  ];

}
