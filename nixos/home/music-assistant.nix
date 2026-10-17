{
  config,
  lib,
  pkgs,
  ...
}:
let
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
  home.activation.configureMusicAssistant = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${lib.getExe configureMusicAssistant}
  '';
}
