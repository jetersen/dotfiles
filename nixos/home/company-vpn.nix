{
  config,
  lib,
  osConfig,
  pkgs,
  openvpnPluginSource,
  ...
}:
let
  python = pkgs.python3.withPackages (ps: [ ps.dbus-python ]);
  plugin = pkgs.runCommand "dms-openvpn3" { } ''
    mkdir -p "$out/helper"
    cp ${openvpnPluginSource}/*.qml ${openvpnPluginSource}/plugin.json \
      ${openvpnPluginSource}/qmldir ${openvpnPluginSource}/LICENSE "$out/"
    cp ${openvpnPluginSource}/helper/*.py "$out/helper/"
    chmod -R u+w "$out"
    substituteInPlace "$out/OpenVpn3Service.qml" "$out/StartupCheck.qml" \
      --replace-fail '"python3"' '"${python}/bin/python3"'
    substituteInPlace "$out/helper/split_dns.py" \
      --replace-fail '"resolvectl"' '"${pkgs.systemd}/bin/resolvectl"'
  '';

in
{
  xdg.configFile = {
    "DankMaterialShell/plugins/openvpn3".source = plugin;
    "dms-openvpn3/application-domains.json".source =
      config.lib.file.mkOutOfStoreSymlink osConfig.sops.secrets.vpn-domains.path;
    "dms-openvpn3/dns.json".text = builtins.toJSON {
      backend = "resolved";
      profiles = lib.genAttrs [ "moviestarplanet" "moviestarplanet-tcp" ] (_: {
        enabled = true;
        file = "${config.xdg.configHome}/dms-openvpn3/application-domains.json";
      });
    };
  };

}
