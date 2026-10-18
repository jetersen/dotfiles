# Rocket: preserve CachyOS and install NixOS

This procedure changes boot files and adds NixOS subvolumes. It does not format,
resize, or delete partitions. Keep the old CachyOS root and EFI backup until
NixOS, the VM, games, and the runner have been tested. The second SSD is temporary
backup storage; it does not protect against loss of the whole machine. Keep the
age recovery identity on another machine and verify it before relying on it.

## Before entering the installer

Build both systems from the approved checkout. Keep that checkout, including
uncommitted configuration files, accessible from the live installer. Record the
built Rocket system path outside `/tmp`; it can be copied into the new Nix store
rather than rebuilt. The installer cache on the second SSD stores that path in
`rocket-system` and includes `dotfiles-source.tar.gz`, a snapshot of tracked and
unignored configuration files without the Git database. Extract it into a private
working directory in the live session to obtain the backup script and host files. Do not activate either system during this preparation.

Copy the managed runner registration's `uuid` and `token` from its current
private registration directory into
`~/.local/state/forgejo-runner/registration/`, owned by UID/GID 1000 with directory
mode 0700 and file mode 0600. Confirm its values match the running runner without
printing them. The backup script requires this canonical location.

First complete the [home and AI state handover review](rocket-home.md), including
browser profile-sync shutdown and AI service version compatibility. Finish CI
jobs and shut down the runner containers gracefully. Shut down the Windows VM
and applications. Enter a RAM-based NixOS installer with kexec, or boot live
media in UEFI mode, with this checkout available. Kexec is only the installer
transition; do not run automatic Disko/formatting phases. Enter one root shell
with `sudo -i`.
Use the installed `tar`, Btrfs tools, util-linux, age, and zstd; if necessary,
start a temporary `nix-shell -p age zstd btrfs-progs`.

## Verify and back up

Verify identities with `lsblk -o NAME,SIZE,FSTYPE,UUID,MODEL,SERIAL`:

| Role | Persistent disk ID | Filesystem UUID |
| --- | --- | --- |
| OS | `nvme-Samsung_SSD_990_PRO_2TB_S6Z2NU0XA27719N` | `20956299-478c-4bbf-8be0-bd0c93caa138` |
| Games and temporary backup | `nvme-Samsung_SSD_9100_PRO_2TB_S7YFNJ0Y408106J` | `d49e4cc0-be81-4381-924a-6891cc37c982` |
| EFI on OS disk | Same OS disk, partition 1 | `B126-967C` |

Mount the old filesystems read-only and the backup filesystem read-write:

```sh
mkdir -p /mnt/rocket-{old,home,srv,efi,games}
mount -o ro,subvol=@ /dev/disk/by-uuid/20956299-478c-4bbf-8be0-bd0c93caa138 /mnt/rocket-old
mount -o ro,subvol=@home /dev/disk/by-uuid/20956299-478c-4bbf-8be0-bd0c93caa138 /mnt/rocket-home
mount -o ro,subvol=@srv /dev/disk/by-uuid/20956299-478c-4bbf-8be0-bd0c93caa138 /mnt/rocket-srv
mount -o ro /dev/disk/by-uuid/B126-967C /mnt/rocket-efi
mount -o subvolid=5 /dev/disk/by-uuid/d49e4cc0-be81-4381-924a-6891cc37c982 /mnt/rocket-games
bash /path/to/dotfiles/scripts/rocket-backup.sh
```

The script checks UUIDs, mount modes, required state, and available space before
writing. It archives all preserved home and srv data, EFI, host keys, pc2mqtt,
Tailscale, libvirt, and the two managed runner volumes. It does not archive the
old host Docker engine, disposable containers, or games already on the second
SSD. It preserves permissions, ACLs, extended attributes, and sparse VM files.
Nothing is excluded from the home archive; if it does not fit, stop and review
what can be omitted rather than deleting data or proceeding without a backup.

Use the printed backup directory in place of BACKUP below. Verify checksums,
then decrypt and read every archive using the separately restored age identity:

```sh
cd BACKUP
sha256sum --check SHA256SUMS
set -o pipefail
for archive in ./*.tar.zst.age; do
  age --decrypt --identity /path/to/recovery-age-key "$archive" | zstd --decompress | tar --list --file=- >/dev/null || exit 1
done
```

Do not keep the sole recovery key inside these archives. Check archived filenames
for the SSH host key, pc2mqtt config, Windows disk/UEFI/TPM files, and runner
registration. Extract representative files into a private temporary directory
and compare their checksums with the read-only sources. Do not install until
archive verification succeeds.

## Installation boundary

Review these steps before executing them. Disko and `nixos-anywhere` formatting
are not part of this procedure. Never use the Framework disk configuration.

1. Mount the OS Btrfs top level separately with `subvolid=5`. Confirm `@`,
   `@home`, and `@srv` exist. Create only **new** `@nixos`, `@nixos-nix`, and
   `@nixos-snapshots`; stop if any already exists, rather than reusing or deleting it.
2. Unmount the backup source mounts before remounting the preserved home and srv
   read-write. Mount `@nixos` at `/mnt/nixos`, then the filesystems declared in
   `nixos/hosts/rocket/filesystems.nix` beneath it. Mount EFI only after its
   verified backup exists. Keep the backup directory on the games disk.
3. Copy the existing SSH host keys to `/mnt/nixos/etc/ssh` with their original
   permissions. Verify the Ed25519 public key matches `nixos/keys/rocket-host.pub`.
   Copy `/var/lib/tailscale` from the old root into its new location with
   restrictive original permissions. Never put it in Nix paths.
4. Use the verified prebuilt Rocket system from the installer cache:

   ```sh
   system=$(cat /mnt/rocket-games/rocket-nixos-install-cache/rocket-system)
   nix --extra-experimental-features 'nix-command flakes' copy --no-check-sigs \
     --from 'file:///mnt/rocket-games/rocket-nixos-install-cache?trusted=true' \
     --to 'local?root=/mnt/nixos' "$system"
   nixos-install --root /mnt/nixos --system "$system" --no-root-passwd
   ```

   The copy accepts unsigned paths from this locally built cache and still
   validates their content hashes. Installation writes NixOS boot files and EFI
   boot configuration.
   Keep the existing CachyOS loader files and the archived EFI tree. Do not
   change the Btrfs default subvolume or delete the old OS.
5. Complete the reviewed offline home handover before the first user login.
   Reboot and choose NixOS. Confirm home ownership, networking, SSH, password
   login, Niri, games, audio, clipboard, and reboot before enabling services below.
   Normal configuration enables Comin automatically. For a new migration,
   temporarily clear `wantedBy` for `comin` and `comin-fetch` until these checks
   pass, then remove those overrides.

## Restore services

Home and srv are reused, not extracted over the active filesystems. Use the
archives only to recover specific files if needed; extract into a staging
directory before overwriting anything.

For the VM, restore images, NVRAM, and swtpm state into the fresh libvirt data
locations while the VM is stopped. Adapt the saved domain XML's emulator,
firmware, and any host-specific paths to the installed NixOS paths before
`virsh define`. NixOS exposes QEMU under `/run/libvirt/nix-emulators/` and runs it
as `qemu-libvirtd`; adjust only the restored VM files' ownership. Check its disk,
UEFI variable store, TPM state, network, and boot in virt-manager. Do not replace
Nix-managed libvirt configuration with the entire old `/etc/libvirt` tree.
For a checksummed Btrfs VM image, use the disk driver's `cache='writeback'`
mode with flushes enabled. Avoid `cache='none'` direct I/O, which can produce
checksum alerts when guest memory changes during a read. Keep filesystem
checksumming enabled and check any alerts against an offline image read and
a read-only scrub before concluding that stored data is damaged.

For the runner, let the fresh Docker engine create the two named local volumes.
With the runner stopped, restore only their `_data` contents, preserving numeric
ownership and sparse files. Do not restore host engine metadata or the old
containerd directory. The Compose file recreates its NFS mount and pinned DinD
image; the nested Docker cache contains CI's Nix store. Verify the canonical
registration directory and Compose configuration, then create
`/var/lib/forgejo-runner/migration-ready` and start `forgejo-runner.service`.
Confirm the registered runner handles a test job before considering it restored.

Desktop boot does not wait for NetworkManager to establish connectivity. A boot
timer starts the runner after 30 seconds; its container health check runs outside
the desktop boot dependency chain and retries failed starts. Use
`systemctl status forgejo-runner` to check readiness.

pc2mqtt's config is encrypted in `nixos/secrets/pc2mqtt.json` for Rocket and the
recovery identity. SOPS decrypts it to `/run/secrets/pc2mqtt-config`, and systemd
passes it through `LoadCredential`. To edit it, run:

```sh
sops --input-type binary --output-type binary nixos/secrets/pc2mqtt.json
```

Config changes restart the service on deployment. Confirm it retains the same
Home Assistant device identity.
Test MQTT connectivity before deliberately testing power commands. Verify
Tailscale retains its enrollment and SSH policy.

## Rollback

If NixOS fails to boot, select the retained CachyOS boot entry or boot the live
installer. Restore the old EFI tree from the verified archive if its entry was
changed. The original `@` root remains intact. Home and srv are shared, so NixOS
activation can change their contents; restore affected files from the verified
home/srv archives when rolling back. Preserve Home Manager's `.pre-nixos` backups.
Do not roll back by restoring the full old host Docker tree into the new engine.
Retain the backups until the migration is accepted and another backup exists.
