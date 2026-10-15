# My dotfiles

NixOS uses the root Nix flake and configuration under `nixos/`.
Other Linux distributions, macOS, and Windows use [chezmoi](https://www.chezmoi.io/)
with `home/` as its source root.

## NixOS

Build the stable NixOS installer with SSH access using `nixos/keys/joseph.pub`:

```sh
nix build .#installer-iso
```

Copy `result/iso/nixos-26.05-framework-installer.iso` into the Zalman's `_iso`
folder. Boot it in UEFI mode with Secure Boot disabled and Ethernet connected.
It starts SSH automatically and advertises `framework-installer.local` through
mDNS. The ISO grants root access to the corresponding SSH private key; it does
not contain that private key or install anything automatically.

For the standard NixOS ISO instead, copy `scripts/nixos-enable-ssh.sh` to the
Zalman's HDD root. In Dual mode, run this from the live console:

```sh
sudo mkdir -p /mnt/zalman
sudo mount /dev/disk/by-label/iODD /mnt/zalman
sudo bash /mnt/zalman/nixos-enable-ssh.sh
```

The Framework configuration uses Niri, DankMaterialShell, DankGreeter, Disko,
and sops-nix.
The initial desktop includes only essential applications from NixOS stable.
DMS and DankGreeter use their upstream flakes pinned to release tags, with
stable nixpkgs.
Zen is pinned separately because it is not available in the stable package set.
Dolphin handles folders and file-manager D-Bus requests; the KDE portal supplies
file-picker dialogs, while Niri's GNOME portal handles screen sharing.
Password login through greetd unlocks GNOME Keyring. DMS screen unlock supports
fingerprints alongside a password fallback; sudo and PolicyKit also accept
fingerprints. Enroll a finger with `fprintd-enroll` after the first login.
DMS's PolicyKit agent provides approval dialogs for `pkexec` in the desktop session.
Its layout is a 2 GiB EFI partition plus a LUKS container containing LVM volumes
for Btrfs and 72 GiB of swap for hibernation. The passphrase file used during
installation is `/tmp/nixos-disk-password` in the live environment; it must not
be committed or copied into the installed system.

Before installation, generate `nixos/hosts/framework/hardware-configuration.nix`
from the Framework using `nixos-generate-config --show-hardware-config
--no-filesystems`, and set `dotfiles.storage.device` in
`nixos/hosts/framework/disk.nix` to its verified `/dev/disk/by-id/` path. The build
refuses to proceed without these. Disko formats the selected disk; review the
target and layout before running an installation.

Host secrets use sops-nix with `/etc/ssh/ssh_host_ed25519_key`. Keep encrypted
secret files in the repo and back up the decryption keys separately. Do not
reference plaintext secrets with Nix paths or `builtins.readFile`, which would
copy them into the Nix store.

Rebuild on an installed Framework from this checkout:

```sh
sudo nixos-rebuild switch --flake .#framework
```

Update pinned dependencies with `nix flake update`. Keep `system.stateVersion`
and `home.stateVersion` unchanged when updating packages. Shared NixOS modules
and the Home Manager configuration can also be used by a future Rocket host.

## Chezmoi installation

### Linux / macOS

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply jetersen
```

### Windows

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force;
iex "&{$(irm 'https://get.chezmoi.io/ps1')} init --apply jetersen"
```

## Chezmoi updates

```sh
chezmoi update
```
