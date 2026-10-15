{
  config,
  lib,
  pkgs,
  dmsSource,
  ...
}:
let
  factoryBinds = pkgs.runCommand "niri-factory-binds.kdl" { } ''
    substitute ${dmsSource}/core/internal/config/embedded/niri-binds.kdl "$out" \
      --replace-fail '{{TERMINAL_COMMAND}}' alacritty
  '';
  dmsSettings = pkgs.writeText "dms-settings.json" (
    builtins.toJSON (
      (import ./dms-settings.nix)
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
      jq --slurpfile overlay ${dmsSettings} -f ${./merge-dms-settings.jq} \
        "$current" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi

      # Seed writable bindings from DMS's own factory template once.
      if [[ ! -s "$config_dir/niri/dms/binds.kdl" ]]; then
        install -m 644 ${factoryBinds} "$config_dir/niri/dms/binds.kdl"
      fi
    '';
  };
in
{
  home.activation.configureDms = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureDms}
  '';

  xdg.userDirs.enable = true;
  xdg.userDirs.createDirectories = true;
  home.file."Pictures/Wallpapers".source = ../../home/Pictures/Wallpapers;
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${pkgs.kdePackages.dolphin}/bin/dolphin --daemon
  '';
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = [ "zen-beta.desktop" ];
      "x-scheme-handler/http" = [ "zen-beta.desktop" ];
      "x-scheme-handler/https" = [ "zen-beta.desktop" ];
      "inode/directory" = [ "org.kde.dolphin.desktop" ];
    };
  };

  xdg.configFile = {
    "alacritty/alacritty.toml".source = ../../home/dot_config/alacritty/alacritty.toml;
    "DankMaterialShell/themes/catppuccin/theme.json".source =
      ../../home/dot_config/DankMaterialShell/themes/catppuccin/theme.json;
    "niri/cfg/input.kdl".source = ../../home/dot_config/niri/cfg/input.kdl;
    "niri/cfg/misc.kdl".source = ../../home/dot_config/niri/cfg/misc.kdl;
    "niri/cfg/animation.kdl".source = ../../home/dot_config/niri/cfg/animation.kdl;
    "niri/cfg/decorations.kdl".source = ../../home/dot_config/niri/cfg/decorations.kdl;
    "niri/config.kdl".text = ''
      include "cfg/input.kdl"
      include "cfg/misc.kdl"

      output "eDP-1" { scale 1.5; }
      workspace "browser"

      layout {
        center-focused-column "never"
        always-center-single-column
        background-color "transparent"
        preset-column-widths {
          proportion 0.33333
          proportion 0.5
          proportion 0.66667
          proportion 1.0
        }
      }

      spawn-at-startup "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1"
      spawn-at-startup "udiskie"
      spawn-sh-at-startup "wl-paste --watch wl-copy --primary"
      spawn-at-startup "zen-browser"

      window-rule { match app-id="zen"; open-on-workspace "browser"; }
      window-rule { geometry-corner-radius 0; clip-to-geometry true; }
      layer-rule { match namespace="^quickshell$"; place-within-backdrop true; }

      include optional=true "dms/colors.kdl"
      include optional=true "dms/layout.kdl"
      include optional=true "dms/alttab.kdl"
      include optional=true "dms/binds.kdl"
      include optional=true "dms/outputs.kdl"
      include optional=true "dms/cursor.kdl"
      include optional=true "dms/windowrules.kdl"

      binds {
        Mod+Return hotkey-overlay-title="Open Terminal: Alacritty" { spawn "alacritty"; }
        Mod+B hotkey-overlay-title="Open Browser: Zen Browser" { spawn "zen-browser"; }
        Mod+E hotkey-overlay-title="File Manager: Dolphin" { spawn "dolphin"; }
        Mod+Print hotkey-overlay-title="Annotate Clipboard Screenshot: Satty" {
          spawn-sh "wl-paste --type image/png | satty -f - --copy-command wl-copy --early-exit"
        }
      }
      include "cfg/animation.kdl"
      include "cfg/decorations.kdl"
    '';
  };
}
