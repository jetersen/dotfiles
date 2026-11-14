{ pkgs, ... }:
let
  shortcodes = pkgs.callPackage ../packages/emoji-shortcodes.nix { };
in
{
  xdg.configFile."espanso/match/emoji.yml".source = "${shortcodes}/emoji.yml";
}
