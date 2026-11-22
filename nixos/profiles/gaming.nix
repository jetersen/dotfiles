# Optional system integration for Steam, including 32-bit graphics and controllers.
{ inputs, pkgs, ... }:
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
        # Install only the Nix package contents, without distribution integration.
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
    extraCompatPackages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.proton-ge ];
    protontricks.enable = true;
  };
  home-manager.users.joseph = {
    home.packages = with pkgs; [
      lutris
    ];
    xdg.configFile."niri/cfg/gaming-rules.kdl".source = ../assets/config/niri/cfg/gaming-rules.kdl;
    dotfiles.niri.extraConfig = ''
      include "cfg/gaming-rules.kdl"
    '';
  };
}
