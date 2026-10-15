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
Slack, Discord, Zed, .NET 10, AWS CLI, kubectl, and Google Cloud CLI use stable
packages. Google Cloud CLI includes the GKE authentication plugin for kubectl.
Zed uses the packaged FHS wrapper for downloaded language servers, with C# and
Nix extensions and the DMS theme. It handles plain text and JSON files; the
terminal editor remains Neovim.
Git also uses Zed for interactive editing, signs commits and tags with the SSH
key matching `nixos/keys/joseph.pub`, and selects the work email for
`moviestarplanet` and `moviestarplanet-archives` remotes. Provision the matching
private key from Proton Pass at `~/.ssh/id_ed25519` with mode `0600`; it stays
outside the repository and Nix store.
Sign in to GitHub CLI from the desktop with
`gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web`.
Its settings remain writable; activation merges the declared defaults while
preserving other settings.

Pulumi uses stable's binary CLI package without its bundled providers and
language hosts. Providers install on demand into the user's Pulumi directory.
The .NET language host is built from source using the pinned
[pulumipkgs recipe](https://github.com/unmango/pulumipkgs), with stable Nixpkgs
dependencies. These packages are also available as `.#pulumi-cli` and
`.#pulumi-language-dotnet`. Cloud and application sign-ins remain user-managed.

Git LFS supplies the wallpaper assets; run `git lfs pull` after cloning if the
checkout contains wallpaper pointer files.
Dolphin handles folders and file-manager D-Bus requests; the KDE portal supplies
file-picker dialogs, while Niri's GNOME portal handles screen sharing.
The KDE Qt integration uses DMS's generated palette for Dolphin and Qt
file-picker dialogs. Matugen generates `kdeglobals` from DMS's color template.
Papirus Dark icons with violet folders are shared across DMS, GTK, and Qt applications.
Password login through greetd unlocks GNOME Keyring. DMS screen unlock supports
fingerprints alongside a password fallback; sudo and PolicyKit also accept
fingerprints. Enroll a finger with `fprintd-enroll` after the first login.
The Framework restarts its fingerprint service across sleep to avoid a stale
Goodix device handle after resume.
DMS's PolicyKit agent provides approval dialogs for `pkexec` in the desktop session.
The Framework supports simultaneous Ethernet and Wi-Fi on the same subnet.
ARP replies and announcements stay on the interface owning the address, and
loose reverse-path checking permits replies through either connected interface.
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

The Framework uses Lanzaboote to sign its boot files on every rebuild. Its
signing keys stay on the encrypted root filesystem in `/var/lib/sbctl`, outside
the Nix store. Back up this directory with age encryption and keep a copy on
another machine. A fresh installation must stage the key bundle at that path
using `nixos-anywhere --extra-files` before installing the bootloader; unsigned
boot files are refused.
After verifying the signed boot files, export the public certificate
`/var/lib/sbctl/keys/db/db.pem` in DER format as `/boot/nixos-secure-boot.cer`.
In the Framework firmware, use Administer Secure Boot, DB Options, Enroll
Signature to add this certificate. Enter the owner GUID from `/var/lib/sbctl/GUID`
when prompted. Retain the existing factory certificates and revocation database,
then enable Enforce Secure Boot. To recover from a boot failure, disable
enforcement in the firmware before booting the installer or a previous
configuration.

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
