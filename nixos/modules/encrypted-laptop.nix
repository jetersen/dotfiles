{ config, lib, ... }:
let
  cfg = config.dotfiles.storage;
in
{
  options.dotfiles.storage = {
    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Verified /dev/disk/by-id path of the disk to install onto.";
    };
    swapSize = lib.mkOption {
      type = lib.types.str;
      description = "Size of the encrypted swap logical volume used for hibernation.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.device != null && lib.hasPrefix "/dev/disk/by-id/" cfg.device;
        message = "Set dotfiles.storage.device to the verified target disk's /dev/disk/by-id path before installing.";
      }
    ];

    # Hide the menu; hold Space at startup to select a rollback generation.
    boot.loader.timeout = 0;
    boot.loader.systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
    boot.loader.efi.canTouchEfiVariables = true;
    boot.initrd.systemd.enable = true;
    console.earlySetup = true;

    disko.devices = {
      disk.system = {
        type = "disk";
        # Guard direct builds of Disko scripts as well as the system build.
        device =
          if cfg.device != null && lib.hasPrefix "/dev/disk/by-id/" cfg.device then
            cfg.device
          else
            throw "Set dotfiles.storage.device to the verified target disk's /dev/disk/by-id path before building Disko scripts.";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "2G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            encrypted = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                # Permit periodic filesystem TRIM through the encrypted device.
                settings.allowDiscards = true;
                passwordFile = "/tmp/nixos-disk-password";
                content = {
                  type = "lvm_pv";
                  vg = "system";
                };
              };
            };
          };
        };
      };
      lvm_vg.system = {
        type = "lvm_vg";
        lvs = {
          swap = {
            size = cfg.swapSize;
            content = {
              type = "swap";
              resumeDevice = true;
            };
          };
          root = {
            size = "100%FREE";
            content = {
              type = "btrfs";
              subvolumes = {
                "/root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };
  };
}
