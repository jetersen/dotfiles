{ pkgs }:
pkgs.writeShellApplication {
  name = "emoji-expansion-control";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.util-linux
    pkgs.systemd
    pkgs.espanso-wayland
    pkgs.python3
  ];
  text = builtins.readFile ./emoji-expansion-control.sh;
}
