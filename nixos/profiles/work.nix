{ pkgs, ... }:
{
  imports = [ ../modules/work.nix ];
  dotfiles.work.enable = true;
  home-manager.users.joseph = {
    imports = [
      ../home/work-cloud.nix
    ];
    home.packages = [ pkgs.slack ];
  };
}
