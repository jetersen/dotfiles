# Ordinary desktop/development composition; company access is opt-in.
{ lib, ... }:
{
  imports = [
    ../modules/virtualisation.nix
    ../modules/gitops.nix
  ];
  options.dotfiles.work.enable = lib.mkEnableOption "company tools and credentials";
  config.home-manager.users.joseph = import ../home/joseph.nix;
}
