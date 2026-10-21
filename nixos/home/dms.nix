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
      source = storageMonitorSource;
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
