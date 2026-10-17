#!/usr/bin/env bash
# Run from the live installer, with CachyOS filesystems mounted read-only as documented.
set -euo pipefail
umask 077
[[ $EUID == 0 ]] || { echo 'Run from the live installer as root.' >&2; exit 1; }
for command in findmnt du df tar zstd age sha256sum; do command -v "$command" >/dev/null; done
recipient=age1u0m8ryqg7hfhuykraxe35v4xzw92a03w9jpt75yv3m57g6pvpp0sf24mdy
system_uuid=20956299-478c-4bbf-8be0-bd0c93caa138
games_uuid=d49e4cc0-be81-4381-924a-6891cc37c982
for source in old home srv; do
  mount=/mnt/rocket-$source
  [[ $(findmnt -nro UUID --mountpoint "$mount") == "$system_uuid" ]]
  [[ ,$(findmnt -nro OPTIONS --mountpoint "$mount"), == *,ro,* ]]
done
[[ $(findmnt -nro FSROOT --mountpoint /mnt/rocket-old) == /@ ]]
[[ $(findmnt -nro FSROOT --mountpoint /mnt/rocket-home) == /@home ]]
[[ $(findmnt -nro FSROOT --mountpoint /mnt/rocket-srv) == /@srv ]]
[[ $(findmnt -nro UUID --mountpoint /mnt/rocket-efi) == B126-967C ]]
[[ ,$(findmnt -nro OPTIONS --mountpoint /mnt/rocket-efi), == *,ro,* ]]
[[ $(findmnt -nro UUID --mountpoint /mnt/rocket-games) == "$games_uuid" ]]
[[ ,$(findmnt -nro OPTIONS --mountpoint /mnt/rocket-games), == *,rw,* ]]
# Refuse the active CachyOS session, even if additional read-only mounts were made.
[[ $(findmnt -nro UUID /) != "$system_uuid" ]]
old=/mnt/rocket-old
paths=(etc/ssh etc/pc2mqtt var/lib/tailscale etc/libvirt var/lib/libvirt
  var/lib/docker/volumes/homelab-forgejo-runner_runner-data/_data
  var/lib/docker/volumes/homelab-forgejo-runner_docker-cache/_data)
for path in "${paths[@]}"; do [[ -e $old/$path ]] || { echo "Missing required state: $path" >&2; exit 1; }; done
[[ -f /mnt/rocket-home/joseph/.local/state/forgejo-runner/registration/uuid ]]
[[ -f /mnt/rocket-home/joseph/.local/state/forgejo-runner/registration/token ]]
# profile-sync-daemon must restore browser profiles from RAM before shutdown.
# A symlink into the old /run or /tmp is not a backup of the profile contents.
shopt -s nullglob
for profile in /mnt/rocket-home/joseph/.mozilla/firefox/* \
  /mnt/rocket-home/joseph/.zen/* /mnt/rocket-home/joseph/.config/BraveSoftware/*; do
  if [[ -L $profile ]]; then
    target=$(readlink -- "$profile")
    if [[ $target == /run/* || $target == /tmp/* ]]; then
      echo "Browser profile still points to volatile storage: $profile" >&2
      exit 1
    fi
  fi
done
# Conservative space check using apparent size; sparse VM files may overestimate.
needed=$(du -sc --apparent-size --block-size=1 /mnt/rocket-home /mnt/rocket-srv /mnt/rocket-efi "${paths[@]/#/$old/}" | tail -1 | cut -f1)
available=$(df --output=avail --block-size=1 /mnt/rocket-games | tail -1)
(( available > needed + 20 * 1024 * 1024 * 1024 )) || { echo 'Insufficient space for an uncompressed-size backup plus 20 GiB reserve.' >&2; exit 1; }
backup=/mnt/rocket-games/rocket-nixos-backup-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -m 700 "$backup"
archive() {
  local name=$1 directory=$2
  shift 2
  tar --create --file=- --directory="$directory" \
    --numeric-owner --acls --xattrs --sparse "$@" \
    | zstd -T2 -3 | age --recipient "$recipient" > "$backup/$name.tar.zst.age.partial"
  mv "$backup/$name.tar.zst.age.partial" "$backup/$name.tar.zst.age"
}
archive home /mnt/rocket-home .
archive srv /mnt/rocket-srv .
archive efi /mnt/rocket-efi .
archive system-state "$old" "${paths[@]}"
(cd "$backup" && sha256sum ./*.tar.zst.age > SHA256SUMS && sha256sum --check SHA256SUMS)
sync
printf 'Encrypted backup written to %s. Decrypt and verify all archives before installing.\n' "$backup"
