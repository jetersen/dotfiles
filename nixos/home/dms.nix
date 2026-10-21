{
  config,
  lib,
  pkgs,
  osConfig,
  dmsSource,
  dmsCommonSource,
  storageMonitorSource,
  ...
}:
let
  storageMonitor = pkgs.runCommand "dms-storage-monitor" { } ''
    cp -r ${storageMonitorSource} "$out"
    chmod -R u+w "$out"
    # Monitoring needs no PyGObject or privileged disk operations.
    substituteInPlace "$out/services/StorageService.qml" \
      --replace-fail '"python3"' '"${pkgs.python3}/bin/python3"'
    substituteInPlace "$out/services/storage_backend.py" \
      --replace-fail '"lsblk"' '"${pkgs.util-linux}/bin/lsblk"' \
      --replace-fail '"findmnt"' '"${pkgs.util-linux}/bin/findmnt"' \
      --replace-fail '"busctl"' '"${pkgs.systemd}/bin/busctl"'
    # A new module URL prevents hot reloads from retaining the old singleton.
    substituteInPlace "$out/StorageMonitorWidget.qml" \
      "$out/StorageMonitorPopout.qml" "$out/StorageMonitorSettings.qml" \
      --replace-fail 'import "./services" as Services' "import \"file:$out/services\" as Services"
    PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 -m unittest discover -s "$out/tests" -v
  '';
  kdePaletteTemplate = pkgs.writeText "kdeglobals-template.colors" (
    builtins.readFile "${dmsSource}/quickshell/matugen/templates/kcolorscheme.colors"
    + ''

      [Icons]
      Theme=Papirus-Dark
    ''
  );
  activation = import ./dms-activation.nix {
    inherit
      config
      lib
      pkgs
      osConfig
      dmsSource
      dmsCommonSource
      ;
  };

in
{
  home.activation.configureDms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe activation.configureDms}
  '';

  home.activation.configureDmsPlugins = lib.hm.dag.entryAfter [ "configureDms" ] ''
    run ${lib.getExe activation.configurePlugins}
  '';

  xdg.configFile = {
    "DankMaterialShell/plugins/storageMonitor" = lib.mkIf osConfig.dotfiles.work.enable {
      source = storageMonitor;
    };
    "matugen/config.toml".source = (pkgs.formats.toml { }).generate "matugen-config.toml" {
      config = { };
      templates.kdeglobals = {
        input_path = "${kdePaletteTemplate}";
        output_path = "${config.xdg.configHome}/kdeglobals";
        post_hook = "${pkgs.dbus}/bin/dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0";
      };
    };
    "DankMaterialShell/themes/catppuccin/theme.json".source =
      ../../home/dot_config/DankMaterialShell/themes/catppuccin/theme.json;

  };
}
