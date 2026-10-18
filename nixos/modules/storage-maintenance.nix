{
  config,
  lib,
  utils,
  ...
}:
{
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    limit = "100M";
  };

  # Persistent timers can catch up after boot; don't start a scrub on battery.
  # The upstream module deduplicates subvolumes and cancels scrubs before sleep.
  systemd.services =
    lib.genAttrs
      (map (fs: "btrfs-scrub-${utils.escapeSystemdPath fs}") config.services.btrfs.autoScrub.fileSystems)
      (_: {
        unitConfig.ConditionACPower = true;
      });
}
