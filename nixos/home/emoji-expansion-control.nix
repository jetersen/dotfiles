{ pkgs }:
pkgs.writeShellApplication {
  name = "emoji-expansion-control";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.util-linux
    pkgs.systemd
  ];
  text = builtins.readFile ./emoji-expansion-control.sh;
}
