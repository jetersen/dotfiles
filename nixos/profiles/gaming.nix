# Optional system integration for Steam, including 32-bit graphics and controllers.
{ pkgs, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      protontricks = prev.protontricks.overrideAttrs (old: {
        # This generated fixture uses [[ ... ]], which /bin/sh cannot run in CI.
        postPatch = (old.postPatch or "") + ''
          substituteInPlace tests/conftest.py \
            --replace-fail '#!/bin/sh' '#!${final.bash}/bin/bash'
        '';
      });
      steam-unwrapped = prev.steam-unwrapped.overrideAttrs {
        # Upstream's default install also writes to /etc/apt when it exists.
        # CI builds without a sandbox; only install the Nix package contents.
        installTargets = [
          "install-bin"
          "install-docs"
          "install-icons"
          "install-bootstrap"
          "install-desktop"
          "install-appdata"
        ];
      };
    })
  ];
  programs.steam = {
    enable = true;
    extraCompatPackages = [ (pkgs.callPackage ../packages/proton-ge.nix { }) ];
    protontricks.enable = true;
  };
  home-manager.users.joseph = {
    home.packages = with pkgs; [
      lutris
    ];
    xdg.configFile."niri/cfg/gaming-rules.kdl".source = ../../home/dot_config/niri/cfg/gaming-rules.kdl;
    dotfiles.niri.extraConfig = ''
      include "cfg/gaming-rules.kdl"
    '';
  };
}
