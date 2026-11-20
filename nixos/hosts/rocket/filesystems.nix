# Existing partitions only. This host intentionally has no Disko format layout.
{
  config,
  pkgs,
  utils,
  ...
}:
let
  goCache = "/media/games/cache/go-build";
  goCacheMount = "${utils.escapeSystemdPath "/home/joseph/.cache/go-build"}.mount";
  systemDisk = "/dev/disk/by-uuid/20956299-478c-4bbf-8be0-bd0c93caa138";
  btrfsOptions = [
    "noatime"
    "compress=zstd"
  ];
  systemSubvolume = subvolume: {
    device = systemDisk;
    fsType = "btrfs";
    options = btrfsOptions ++ [ "subvol=${subvolume}" ];
  };
in
{
  # Existing NixOS subvolumes and shared data; never recreate or format them.
  fileSystems."/" = systemSubvolume "@nixos";
  fileSystems."/nix" = systemSubvolume "@nixos-nix";
  fileSystems."/.snapshots" = systemSubvolume "@nixos-snapshots";
  fileSystems."/home" = systemSubvolume "@home";
  fileSystems."/srv" = systemSubvolume "@srv";
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/B126-967C";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };
  fileSystems."/media/games" = {
    device = "/dev/disk/by-uuid/d49e4cc0-be81-4381-924a-6891cc37c982";
    fsType = "btrfs";
    options = btrfsOptions;
  };
  fileSystems."/home/joseph/.local/share/Steam" = {
    device = "/media/games/Steam";
    fsType = "none";
    options = [ "bind" ];
    depends = [
      "/home"
      "/media/games"
    ];
  };
  # Keep the default path for already-running shells and agents.
  fileSystems."/home/joseph/.cache/go-build" = {
    device = goCache;
    fsType = "none";
    options = [ "bind" ];
    depends = [
      "/home"
      "/media/games"
    ];
  };
  systemd.services.go-build-cache-directory = {
    description = "Prepare Go build cache on the data SSD";
    requiredBy = [ goCacheMount ];
    before = [ goCacheMount ];
    # This mount is part of local-fs.target, so the preparation service must
    # not acquire the normal service ordering after basic.target.
    unitConfig = {
      DefaultDependencies = false;
      RequiresMountsFor = [
        "/media/games"
        "/nix"
      ];
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/install -d -m 0700 -o ${toString config.users.users.joseph.uid} -g ${toString config.users.groups.joseph.gid} ${goCache}";
    };
  };
  swapDevices = [ ];
  zramSwap.enable = true;
}
