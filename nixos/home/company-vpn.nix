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
  enablePlugin = pkgs.writeShellApplication {
    name = "enable-openvpn-plugin";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      settings="$config_dir/DankMaterialShell/plugin_settings.json"
      current=/dev/stdin
      if [[ -s "$settings" ]]; then current="$settings"; fi
      temporary=$(mktemp "$(dirname "$settings")/.plugins.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq '.openvpn3.enabled = true' "$current" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi
    '';
  };
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

  home.activation.enableOpenvpnPlugin = lib.hm.dag.entryAfter [ "configureDms" ] ''
    run ${lib.getExe enablePlugin}
  '';
}
