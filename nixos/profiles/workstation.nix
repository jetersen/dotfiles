# Ordinary desktop/development composition; company access is opt-in.
{ lib, pkgs, ... }:
{
  imports = [
    ../modules/virtualisation.nix
    ../modules/gitops.nix
    ../modules/storage-maintenance.nix
    ../modules/work-environment.nix
  ];
  options.dotfiles.work.enable = lib.mkEnableOption "company tools and credentials";
  config = {
    home-manager.users.joseph = import ../home/joseph.nix;

    # Aspire extracts Linux bundles; T3 downloads Chrome Headless Shell.
    # Keep their loader libraries at nix-ld's stable system path so existing
    # T3 servers can launch newly downloaded browsers without restarting.
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        icu
        alsa-lib
        at-spi2-core
        dbus
        expat
        glib
        libgbm
        libx11
        libxcb
        libxcomposite
        libxdamage
        libxext
        libxfixes
        libxkbcommon
        libxrandr
        nspr
        nss
      ];
    };

    # Monitor application workloads; the compositor and session services live
    # in session.slice and remain outside this pressure-based kill policy.
    systemd.oomd.enable = true;
    systemd.user.slices.app = {
      overrideStrategy = "asDropin";
      sliceConfig = {
        ManagedOOMMemoryPressure = "kill";
        ManagedOOMMemoryPressureLimit = "80%";
      };
    };
  };
}
