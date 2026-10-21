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

    # Aspire extracts generic Linux DCP, Dashboard and managed host binaries.
    # Patching the Nix-managed CLI alone does not make its bundle executable.
    programs.nix-ld = {
      enable = true;
      libraries = [ pkgs.icu ];
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
