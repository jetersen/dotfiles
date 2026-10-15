# Keep wallpaper binaries outside dotfiles and verify downloads with Nix.
{ pkgs }:
pkgs.linkFarm "wallpapers" [
  {
    name = "clearnight.jpg";
    path = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/zhichaoh/catppuccin-wallpapers/1023077979591cdeca76aae94e0359da1707a60e/landscapes/Clearnight.jpg";
      hash = "sha256-scfoYBzVdRH4NytizwI938JFbfayeIdsne0FYCdsnfk=";
    };
  }
]
