# Ordinary desktop/development composition; company access is opt-in.
{ lib, ... }:
{
  imports = [
    ../modules/virtualisation.nix
    ../modules/gitops.nix
  ];
  options.dotfiles.work.enable = lib.mkEnableOption "company tools and credentials";
  config = {
    home-manager.users.joseph = import ../home/joseph.nix;

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
