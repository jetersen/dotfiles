{ config, lib, ... }:
let
  cfg = config.dotfiles.niri;
  workspaceDeclaration =
    name:
    let
      output = cfg.workspaceOutputs.${name} or null;
    in
    "workspace ${builtins.toJSON name}"
    + lib.optionalString (output != null) " { open-on-output ${builtins.toJSON output}; }";
in
{
  options.dotfiles.niri = {
    workspaceOutputs = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Preferred output names for browser, chat, and music workspaces; absent outputs fall back automatically.";
    };
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional host or profile Niri rules.";
    };
  };
  config.xdg.configFile = {
    "niri/cfg/music.kdl".source = ../../home/dot_config/niri/cfg/music.kdl;
    "niri/cfg/input.kdl".source = ../../home/dot_config/niri/cfg/input.kdl;
    "niri/cfg/misc.kdl".source = ../../home/dot_config/niri/cfg/misc.kdl;
    "niri/cfg/keybinds.kdl".source = ../../home/dot_config/niri/cfg/keybinds.kdl;
    "niri/cfg/animation.kdl".source = ../../home/dot_config/niri/cfg/animation.kdl;
    "niri/cfg/decorations.kdl".source = ../../home/dot_config/niri/cfg/decorations.kdl;
    "niri/cfg/shared-rules.kdl".source = ../../home/dot_config/niri/cfg/shared-rules.kdl;
    "niri/config.kdl".text = ''
      include "cfg/input.kdl"
      include "cfg/misc.kdl"

      environment {
        QT_QPA_PLATFORMTHEME "xdgdesktopportal"
        QT_QPA_PLATFORMTHEME_QT6 "xdgdesktopportal"
      }

      ${lib.concatMapStringsSep "\n" workspaceDeclaration [
        "browser"
        "chat"
        "music"
      ]}
      include "cfg/music.kdl"

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

      spawn-at-startup "udiskie"
      spawn-sh-at-startup "wl-paste --watch wl-copy --primary"
      spawn-at-startup "zen-browser"

      include "cfg/shared-rules.kdl"

      include optional=true "dms/colors.kdl"
      include optional=true "dms/layout.kdl"
      include optional=true "dms/alttab.kdl"
      include optional=true "dms/binds.kdl"
      include optional=true "dms/outputs.kdl"
      include optional=true "dms/cursor.kdl"
      include optional=true "dms/windowrules.kdl"

      include "cfg/keybinds.kdl"
      include "cfg/animation.kdl"
      include "cfg/decorations.kdl"
      ${cfg.extraConfig}
    '';
  };
}
