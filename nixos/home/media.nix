{
  config,
  lib,
  pkgs,
  ...
}:
let
  pearSettings = pkgs.writeText "pear-settings.json" (
    builtins.toJSON {
      options = {
        tray = true;
        appVisible = false;
        autoUpdates = false;
        # Open the home page so YouTube Music can restore the latest device queue.
        resumeOnStart = false;
      };
      plugins = {
        video-toggle = {
          enabled = true;
          hideVideo = true;
          forceHide = true;
        };
        discord.enabled = true;
        shortcuts.enabled = true;
        api-server.enabled = false;
      };
    }
  );
  configurePear = pkgs.writeShellApplication {
    name = "configure-pear";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config_dir="''${XDG_CONFIG_HOME:-$HOME/.config}/YouTube Music"
      mkdir -p "$config_dir"
      settings="$config_dir/config.json"
      current=/dev/stdin
      if [[ -s "$settings" ]]; then current="$settings"; fi
      temporary=$(mktemp "$config_dir/.config.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      jq --slurpfile overlay ${pearSettings} '. * $overlay[0]' \
        "$current" <<< '{}' > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi
    '';
  };
  configureMusicAssistant = pkgs.writeShellApplication {
    name = "configure-music-assistant";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      settings=${lib.escapeShellArg "${config.xdg.configHome}/music-assistant-companion/settings.json"}
      umask 077
      mkdir -p "$(dirname "$settings")"
      current=/dev/null
      if [[ -e "$settings" ]]; then current="$settings"; fi
      temporary=$(mktemp "$(dirname "$settings")/.settings.XXXXXX")
      trap 'rm -f "$temporary"' EXIT
      ${pkgs.bash}/bin/bash ${../../home/dot_config/music-assistant-companion/modify_settings.json} \
        < "$current" > "$temporary"
      if ! cmp -s "$temporary" "$settings"; then mv "$temporary" "$settings"; fi
    '';
  };
in
{
  programs.mpv.enable = true;

  home.activation.configurePear = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configurePear}
  '';

  home.packages = [
    (pkgs.callPackage ../packages/music-assistant-desktop.nix { })
    pkgs.pear-desktop
    (pkgs.writeShellApplication {
      name = "focus-music-assistant";
      runtimeInputs = [
        pkgs.niri
        pkgs.jq
        pkgs.systemd
        (pkgs.callPackage ../packages/music-assistant-desktop.nix { })
      ];
      text = ''
        exec ${pkgs.bash}/bin/bash ${../../home/dot_local/bin/executable_focus-music-assistant} "$@"
      '';
    })
  ];

  home.activation.configureMusicAssistant = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureMusicAssistant}
  '';
}
