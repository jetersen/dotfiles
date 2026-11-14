{ pkgs }:
let
  source = pkgs.fetchFromGitHub {
    owner = "github";
    repo = "gemoji";
    rev = "fadaeaf1f1a9be82b321316a6c5502e43138b2f6";
    hash = "sha256-ZTtqpPaZCA0VZ/ifs1gs41GJ9yGY6xgxSi+N63bvoW4=";
  };
in
pkgs.runCommand "emoji-shortcodes" { } ''
  mkdir -p "$out"
  ${pkgs.python3}/bin/python3 ${./generate-emoji-shortcodes.py} \
    ${source}/db/emoji.json ${../home/emoji-shortcodes.json} "$out"
  cp ${source}/LICENSE "$out/LICENSE-gemoji"
''
