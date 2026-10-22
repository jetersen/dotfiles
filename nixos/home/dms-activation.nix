{
  config,
  lib,
  pkgs,
  osConfig,
  dmsSource,
  dmsCommonSource,
}:
let
  dms = lib.escapeShellArg (lib.getExe osConfig.programs.dms-shell.package);
  factoryBinds = pkgs.runCommand "niri-factory-binds.kdl" { } ''
    substitute ${dmsSource}/core/internal/config/embedded/niri-binds.kdl "$out" \
      --replace-fail '{{TERMINAL_COMMAND}}' alacritty
  '';
  dmsAppIdDefaults =
    pkgs.runCommand "dms-app-id-defaults.json" { nativeBuildInputs = [ pkgs.nodejs ]; }
      ''
        node ${./read-dms-app-id-defaults.mjs} ${dmsSource} ${dmsCommonSource} > "$out"
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
        cursorSettings = {
          theme = config.home.pointerCursor.name;
          size = config.home.pointerCursor.size;
        };
      }
    )
  );
  configureDms = pkgs.writeShellApplication {
    name = "configure-dms";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.jq
      pkgs.gnugrep
      pkgs.gnused
      osConfig.programs.niri.package
    ];
    derivationArgs.postCheck = ''
      ${pkgs.python3}/bin/python3 ${../../tests/test_dms_activation.py} "$target"
    '';
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

      # Reserve Alt+Space for switching keyboard layouts, including on first login.
      ${dms} keybinds remove niri Alt+Space

      # Keep both hosts on DMS screenshots, including bindings seeded by older Niri defaults.
      for key in Print XF86Launch1; do
        ${dms} keybinds set niri "$key" 'spawn "dms" "screenshot"' --desc 'Screenshot: Region'
        ${dms} keybinds set niri "Ctrl+$key" 'spawn "dms" "screenshot" "full"' --desc 'Screenshot: Full Screen'
        ${dms} keybinds set niri "Alt+$key" 'spawn "dms" "screenshot" "window"' --desc 'Screenshot: Window'
      done
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
      pkgs.diffutils
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
  inherit
    configureDms
    configurePlugins
    dmsSettings
    pluginSettings
    ;
}
