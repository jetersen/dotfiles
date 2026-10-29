{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 10485760;
    "fs.inotify.max_user_instances" = 8192;
    "fs.inotify.max_queued_events" = 262144;
  };

  # Keep the remote recovery path resident when desktop workloads exhaust memory.
  # Protection must also be allocated at the parent slice.
  systemd.slices.system.sliceConfig.MemoryMin = "1G";
  imports = [
    {
      systemd.services = lib.genAttrs [ "sshd" "tailscaled" "NetworkManager" "systemd-resolved" ] (name: {
        serviceConfig = {
          MemoryMin = if name == "tailscaled" then "512M" else "128M";
          OOMScoreAdjust = -1000;
          ManagedOOMPreference = "omit";
        };
      });
    }
  ];

  # The existing Forgejo Compose deployment needs privileged DinD and named volumes.
  # Restore only the managed runner volumes/registration into a fresh Docker data root.
  # Keep the old CachyOS Docker/containerd directories intact as recovery sources.
  virtualisation.docker = {
    enable = true;
    rootless.enable = lib.mkForce false;
    rootless.setSocketVariable = lib.mkForce false;
    autoPrune.enable = false;
  };
  users.users.joseph.extraGroups = [ "docker" ];

  environment.etc."homelab-dns/config.json".text = builtins.toJSON {
    mode = "magic-only";
  };
  systemd.services.homelab-dns-reconcile = {
    description = "Maintain homelab MagicDNS and VPN DNS routing";
    wantedBy = [ "multi-user.target" ];
    wants = [ "systemd-resolved.service" ];
    after = [
      "systemd-resolved.service"
      "tailscaled.service"
    ];
    path = [
      pkgs.systemd
      config.services.tailscale.package
    ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${../../../home/dot_local/share/homelab-dns/reconcile.py}";
      Restart = "always";
      RestartSec = 3;
      StateDirectory = "homelab-dns";
      StateDirectoryMode = "0755";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ReadWritePaths = [ "/var/lib/homelab-dns" ];
    };
  };

  # Retain the current cleanup policy; do not create periodic or boot snapshots.
  # The host mounts a new @nixos-snapshots at /.snapshots, separate from CachyOS snapshots.
  services.snapper = {
    snapshotRootOnBoot = false;
    configs.root = {
      SUBVOLUME = "/";
      FSTYPE = "btrfs";
      SPACE_LIMIT = "0.5";
      FREE_LIMIT = "0.2";
      NUMBER_CLEANUP = true;
      NUMBER_MIN_AGE = 1800;
      NUMBER_LIMIT = "50";
      NUMBER_LIMIT_IMPORTANT = "15";
      TIMELINE_CREATE = false;
      TIMELINE_CLEANUP = true;
      TIMELINE_MIN_AGE = 1800;
      TIMELINE_LIMIT_HOURLY = "5";
      TIMELINE_LIMIT_DAILY = "7";
      TIMELINE_LIMIT_WEEKLY = "0";
      TIMELINE_LIMIT_MONTHLY = "0";
      TIMELINE_LIMIT_YEARLY = "0";
      EMPTY_PRE_POST_CLEANUP = true;
      EMPTY_PRE_POST_MIN_AGE = 1800;
    };
  };
}
