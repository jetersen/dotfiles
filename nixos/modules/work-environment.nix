{ ... }:
{
  sops.secrets.varlock-work-schema = {
    sopsFile = ../secrets/varlock.yaml;
    owner = "joseph";
    group = "users";
    mode = "0600";
  };
  home-manager.users.joseph.imports = [ ../home/work-environment.nix ];
}
