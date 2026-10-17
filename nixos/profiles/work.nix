# Import with nixosModules.work so the company VPN input is supplied too.
{ pkgs, ... }:
{
  imports = [ ../modules/work.nix ];
  dotfiles.work.enable = true;
  home-manager.users.joseph = {
    imports = [
      ../home/work-cloud.nix
      ../home/work-environment.nix
      ../home/argocd-remote-sso.nix
    ];
    home.packages = [ pkgs.slack ];
  };
}
