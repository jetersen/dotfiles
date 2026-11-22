{ pkgs }:
let
  source = pkgs.fetchFromGitHub {
    owner = "github";
    repo = "gemoji";
    rev = "fadaeaf1f1a9be82b321316a6c5502e43138b2f6";
    hash = "sha256-ZTtqpPaZCA0VZ/ifs1gs41GJ9yGY6xgxSi+N63bvoW4=";
  };
in
pkgs.runCommand "emoji-shortcodes" { nativeBuildInputs = [ pkgs.jq ]; } ''
  mkdir -p "$out"
  jq --slurpfile custom ${../home/emoji-shortcodes.json} -f ${./emoji-shortcodes.jq} \
    ${source}/db/emoji.json > catalog.json
  jq -c '.shortcodes' catalog.json > "$out/shortcodes.json"
  # Espanso accepts JSON as YAML.
  jq -c '{matches}' catalog.json > "$out/emoji.yml"
  jq -r '"var byEmoji = \(.byEmoji | tojson);", "var customEntries = \(.customEntries | tojson);"' \
    catalog.json > "$out/EmojiShortcodes.js"
  cp ${source}/LICENSE "$out/LICENSE-gemoji"
''
