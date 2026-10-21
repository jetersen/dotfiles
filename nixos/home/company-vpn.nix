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
    # Dependencies are supplied by Nix. A transient D-Bus activation failure
    # must not prevent loading the widget that retries service discovery.
    ${python}/bin/python3 - "$out/plugin.json" <<'PYTHON'
    import json
    import pathlib
    import sys
    path = pathlib.Path(sys.argv[1])
    manifest = json.loads(path.read_text())
    del manifest["startupCheck"]
    path.write_text(json.dumps(manifest) + "\n")
    PYTHON
    # Reuse the existing 60-second refresh for CLI sessions, late DNS metadata
    # and OpenVPN overwrites, including after a transient sync failure.
    substituteInPlace "$out/OpenVpn3Service.qml" \
      --replace-fail 'function refresh(updateDns = false)' 'function refresh(updateDns = true)'
    substituteInPlace "$out/helper/split_dns.py" \
      --replace-fail '"resolvectl"' '"${pkgs.systemd}/bin/resolvectl"'
  '';

  dnsCheck = pkgs.runCommand "openvpn-dns-regression" { } ''
    ${python}/bin/python3 ${../../tests/test_company_vpn_dns.py} ${plugin} ${pkgs.nodejs}/bin/node
    touch "$out"
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

  # Let OpenVPN keep unrelated DNS off the tunnel even before plugin sync.
  # Existing profiles retain their credentials and other overrides.
  home.activation.configureWorkVpnDns = lib.mkIf osConfig.services.resolved.enable (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      for profile in moviestarplanet moviestarplanet-tcp; do
        if ${pkgs.openvpn3}/bin/openvpn3 config-manage --config "$profile" --exists --quiet; then
          $DRY_RUN_CMD ${pkgs.openvpn3}/bin/openvpn3 config-manage --config "$profile" --dns-scope tunnel
        fi
      done
    ''
  );

  # Run the regression suite whenever this integration is built.
  home.extraDependencies = [ dnsCheck ];
}
