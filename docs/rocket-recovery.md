# Rocket storage and recovery

Rocket uses existing partitions and Btrfs subvolumes managed by
`nixos/hosts/rocket/filesystems.nix`. Do not run Disko, format partitions, or
recreate the subvolumes during recovery.

## Disk layout

Verify identities with `lsblk -o NAME,SIZE,FSTYPE,UUID,MODEL,SERIAL`; NVMe device
numbers can change between boots.

| Role | Persistent disk ID | Filesystem UUID |
| --- | --- | --- |
| OS | `nvme-Samsung_SSD_990_PRO_2TB_S6Z2NU0XA27719N` | `20956299-478c-4bbf-8be0-bd0c93caa138` |
| Games | `nvme-Samsung_SSD_9100_PRO_2TB_S7YFNJ0Y408106J` | `d49e4cc0-be81-4381-924a-6891cc37c982` |
| EFI on OS disk | Same OS disk, partition 1 | `B126-967C` |

| Mount | OS subvolume |
| --- | --- |
| `/` | `@nixos` (also the Btrfs default) |
| `/nix` | `@nixos-nix` |
| `/.snapshots` | `@nixos-snapshots` |
| `/home` | `@home` |
| `/srv` | `@srv` |

The games filesystem mounts at `/media/games`; its `Steam` directory binds to
`/home/joseph/.local/share/Steam`. Home data uses UID/GID 1000.

CachyOS roots, snapshots, boot files, migration archives, installer cache, and
temporary VM recovery copies are retired. Recovery uses NixOS generations or
live media and independently maintained backups. Snapshots on the same disk do
not protect against disk loss.

## Boot recovery

Hold Space during startup to select an older NixOS generation in systemd-boot.
Booting an older generation does not restore home files, databases, or VM disks.

If no generation boots, start a NixOS installer in UEFI mode. Verify the disk
identities above, then mount the existing installation as root:

```sh
os=/dev/disk/by-uuid/20956299-478c-4bbf-8be0-bd0c93caa138
mount -o subvol=@nixos "$os" /mnt
mkdir -p /mnt/{nix,home,srv,.snapshots,boot}
mount -o subvol=@nixos-nix "$os" /mnt/nix
mount -o subvol=@home "$os" /mnt/home
mount -o subvol=@srv "$os" /mnt/srv
mount -o subvol=@nixos-snapshots "$os" /mnt/.snapshots
mount /dev/disk/by-uuid/B126-967C /mnt/boot
```

Inspect the installed profiles with
`ls -l /mnt/nix/var/nix/profiles/system*-link`. To reinstall the bootloader from
the current system profile without rebuilding or replacing data:

```sh
nixos-enter --root /mnt -c 'NIXOS_INSTALL_BOOTLOADER=1 /nix/var/nix/profiles/system/bin/switch-to-configuration boot'
```

If that profile is damaged, select a known-good existing `system-N-link` in the
same command. Reboot after checking the EFI loader entries. Once the machine is
accessible, use the normal CI/cache/`nixos-upgrade.service` deployment path.

## Application data

Windows uses `/var/lib/libvirt/images/win11.qcow2`, its firmware variables under
`/var/lib/libvirt/qemu/nvram/`, and TPM state under `/var/lib/libvirt/swtpm/`.
Back up and restore the disk, firmware variables, TPM state, and domain XML
together while the VM is shut down. Stage restored files separately and preserve
the current state before replacing anything. The disk driver uses
`cache='writeback'` with flushes enabled; keep Btrfs checksumming enabled.

Keep the runner registration under
`~/.local/state/forgejo-runner/registration/` private. Recover the runner's named
volume contents into a fresh Docker engine while the runner is stopped; do not
restore an old host Docker or containerd metadata tree.

Preserve SSH host keys, Tailscale state, application profiles, and credentials in
independent backups. Keep recovery identities off the machine. SOPS-managed
secrets remain encrypted in the repository and decrypt into `/run/secrets`.
