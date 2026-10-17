# Existing partitions only. This host intentionally has no Disko format layout.
{ ... }:
let
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
  # Create only these new subvolumes during the reviewed live-USB installation.
  # Keep CachyOS's @ and @/.snapshots intact for recovery.
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
  swapDevices = [ ];
  zramSwap.enable = true;
}
