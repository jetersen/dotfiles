{
  config,
  lib,
  pkgs,
  ...
}:
let
  pkiBundle = config.boot.lanzaboote.pkiBundle;
in
{
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    allowUnsigned = false;
  };

  environment.systemPackages = [ pkgs.sbctl ];
  environment.etc."sbctl/sbctl.conf".source = (pkgs.formats.yaml { }).generate "sbctl.conf" {
    keydir = "${pkiBundle}/keys";
    guid = "${pkiBundle}/GUID";
    files_db = "${pkiBundle}/files.json";
    bundles_db = "${pkiBundle}/bundles.json";
  };
}
