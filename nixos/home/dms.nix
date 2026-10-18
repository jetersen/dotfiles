{
  config,
  lib,
  pkgs,
  osConfig,
  dmsSource,
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
  factoryBinds = pkgs.runCommand "niri-factory-binds.kdl" { } ''
    substitute ${dmsSource}/core/internal/config/embedded/niri-binds.kdl "$out" \
      --replace-fail '{{TERMINAL_COMMAND}}' alacritty
  '';
  dmsAppIdDefaults =
    pkgs.runCommand "dms-app-id-defaults.json" { nativeBuildInputs = [ pkgs.nodejs ]; }
      ''
        node - '${dmsSource}/quickshell/Common/settings/SettingsSpec.js' > "$out" <<'JS'
        const fs = require("node:fs");
        const source = fs.readFileSync(process.argv[2], "utf8").replace(/^\s*\.(pragma|import)\b.*$/gm, "");
        const defaults = new Function(source + "\nreturn SPEC.appIdSubstitutions.def;")();
        process.stdout.write(JSON.stringify(defaults));
        JS
      '';
  dmsSettings = pkgs.writeText "dms-settings.json" (
    builtins.toJSON (
      (import ./dms-settings.nix {
        enableFprint = osConfig.services.fprintd.enable;
        extraRightWidgets =
          lib.optional osConfig.programs.openvpn3.enable "openvpn3"
          ++ lib.optional osConfig.dotfiles.work.enable "storageMonitor";
      })
      // {
        customThemeFile = "${config.xdg.configHome}/DankMaterialShell/themes/catppuccin/theme.json";
      }
    )
  );
  configureDms = pkgs.writeShellApplication {
    name = "configure-dms";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}"
      mkdir -p "$config_dir/DankMaterialShell" "$config_dir/niri/dms"
      settings="$config_dir/DankMaterialShell/settings.json"
      current=/dev/stdin
      if [[ -s "$settings" ]]; then current="$settings"; fi
      temporary=$(mktemp "$config_dir/DankMaterialShell/.settings.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq --slurpfile overlay ${dmsSettings} --slurpfile appIdDefaults ${dmsAppIdDefaults} \
        -f ${./merge-dms-settings.jq} \
        "$current" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi

      if [[ -s "$config_dir/gtk-3.0/dank-colors.css" && -s "$config_dir/gtk-4.0/dank-colors.css" ]]; then
        export XDG_DATA_DIRS="${pkgs.adw-gtk3}/share:''${XDG_DATA_DIRS:-/run/current-system/sw/share}"
        ${pkgs.bash}/bin/bash ${dmsSource}/quickshell/scripts/gtk.sh "$config_dir" apply false
        ${pkgs.bash}/bin/bash ${dmsSource}/quickshell/scripts/gtk.sh "$config_dir" patch false
      fi

      # Seed writable bindings from DMS's own factory template once.
      if [[ ! -s "$config_dir/niri/dms/binds.kdl" ]]; then
        install -m 644 ${factoryBinds} "$config_dir/niri/dms/binds.kdl"
      fi
    '';
  };
  plugins =
    lib.optionalAttrs osConfig.programs.openvpn3.enable { openvpn3.enabled = true; }
    // lib.optionalAttrs osConfig.dotfiles.work.enable { storageMonitor.enabled = true; };
  pluginSettings = pkgs.writeText "dms-plugins.json" (builtins.toJSON plugins);
  configurePlugins = pkgs.writeShellApplication {
    name = "configure-dms-plugins";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      settings="''${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugin_settings.json"
      current=/dev/stdin
      if [[ -s "$settings" ]]; then current="$settings"; fi
      temporary=$(mktemp "$(dirname "$settings")/.plugins.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq --slurpfile overlay ${pluginSettings} '. * $overlay[0]' "$current" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi
    '';
  };

in
{
  home.activation.configureDms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureDms}
  '';

  home.activation.configureDmsPlugins = lib.hm.dag.entryAfter [ "configureDms" ] ''
    run ${lib.getExe configurePlugins}
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
