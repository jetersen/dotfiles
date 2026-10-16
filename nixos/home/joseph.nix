{ pkgs, dotfilesPackages, ... }:
{
  imports = [
    ./ai-tools.nix
    ./cloud.nix
    ./desktop.nix
    ./development.nix
    ./direnv.nix
    ./git.nix
    ./local-git-sync.nix
    ./shell.nix
    ./ssh.nix
    ./prompt.nix
    ./workstation.nix
    ./work-environment.nix
  ];
  home.username = "joseph";
  home.homeDirectory = "/home/joseph";
  home.stateVersion = "26.05";

  services.local-git-sync = {
    enable = true;
    package = dotfilesPackages.local-git-sync;
  };

  home.sessionVariables = {
    EDITOR = "zeditor --wait";
    BROWSER = "zen-browser";
  };

  home.packages = with pkgs; [
    eza
    ripgrep
  ];

}
