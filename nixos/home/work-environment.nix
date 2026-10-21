{
  config,
  dotfilesPackages,
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  varlock = dotfilesPackages.varlock;
in
{
  home.file.".config/varlock/work/.env.schema".source =
    config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.varlock-work-schema.path;

  home.packages = [
    varlock
    pkgs.bitwarden-cli
    (pkgs.writeShellApplication {
      name = "workenv";
      text = ''
        if (( $# == 0 )); then
          echo 'Usage: workenv COMMAND [ARGUMENTS...]' >&2
          exit 2
        fi
        exec ${lib.getExe varlock} run -p "$HOME/.config/varlock/work/.env.schema" -- "$@"
      '';
    })
  ];
}
