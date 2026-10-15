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

Claude Code uses Anthropic's upstream release manifest with stable Nixpkgs'
native packaging. Run `nixos/packages/update-claude-code.sh` to pin the latest
release, or pass a specific version. Review the manifest diff and rebuild NixOS;
Nix verifies the binary against the manifest's checksum.
Codex CLI and T3 Code use a separate pinned `nixpkgs-unstable` input. Update them
with `nix flake update nixpkgs-unstable`, then rebuild NixOS.
T3 Code includes both provider CLIs on its runtime path, using the same Claude
version as the terminal. Launch `claude`, `codex`, or `t3code-desktop`; `t3` runs
the web interface. Sign in locally with `claude auth login` and `codex login`.
Credentials and application state remain user-managed outside the Nix store.
Application binaries update through Nix rather than their own installers.

Forgejo is the primary repository at `forgejo.jetersen.dev/jetersen/dotfiles`.
The GitHub repository remains a push mirror for existing chezmoi installations;
Forgejo Actions mirrors Git commits, tags, and LFS objects using a deploy key
limited to that GitHub repository.

The homelab's Renovate job opens dependency updates on Forgejo, including Claude's
upstream manifest and flake lock maintenance. NixOS CI builds the Framework on
Rocket and uploads its complete closure to the private Attic cache. Only then
does it advance `deploy/framework` to that exact commit. Comin follows that branch
and applies updates automatically when it can reach Forgejo and the cache.
Its Nix process disables local builds, so missing cached files postpone an update.
Interactive Nix commands can still build normally. Merging an update enables its
deployment after CI succeeds; CI does not receive the laptop's decryption or
Secure Boot private keys. Kernel changes still require a reboot to take effect.

Cache access uses the encrypted `nix-cache-netrc` secret and the public signing
key declared in `nixos/modules/gitops.nix`. Keep prior boot generations for
rollback. To stop automatic updates while diagnosing a problem, run
`sudo systemctl stop comin`; start it again after correcting or reverting the
deployment revision. Reverting only the running system is temporary while Comin
still follows a newer deployment commit.

Git also uses Zed for interactive editing, signs commits and tags with the SSH
key matching `nixos/keys/joseph.pub`, and selects the work email for
`moviestarplanet` and `moviestarplanet-archives` remotes. Provision the matching
private key from Proton Pass at `~/.ssh/id_ed25519` with mode `0600`; it stays
outside the repository and Nix store.
Sign in to GitHub CLI from the desktop with
`gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web`.
Its settings remain writable; activation merges the declared defaults while
preserving other settings.
Forgejo CLI (`fj`) uses stable Nixpkgs for homelab repository operations.
Authenticate it separately for `forgejo.jetersen.dev`; its login state remains
user-managed outside the Nix store.

The NixOS Fish prompt uses stable Starship with two lines: path, Git state,
relevant runtimes above the command marker. Remote SSH and mosh
sessions show `user@host`; failures show the exit code, and commands taking at
least two seconds show their duration. Prompt history retains this information.
The Framework shows battery percentage while unplugged, in red at 20% or below.

AWS and Kubernetes context are omitted from the prompt. Direnv manages project
environments through each repository's `.envrc`; review it and run `direnv allow`
after cloning or changing it. In `homelab` and `dotfiles`, it prepends the
Home Manager-provided kubeconfig overlay to select `homelab` without rewriting
the encrypted kubeconfig. It also applies in subdirectories. Leaving restores
the previous environment. Where the overlay is absent, the `.envrc` preserves
the existing configuration. Explicit `--context` still wins. Use
`direnv exec /path/to/repo COMMAND` to load a trusted project environment for a
noninteractive command; automation should select its context explicitly.
Other platforms retain their existing Oh My Posh setup.

The Framework's AWS SSO profiles and Kubernetes configuration are encrypted in
`nixos/secrets/framework.yaml` as `aws-config` and `kube-config`. Home Manager
links the decrypted, user-owned files into `~/.aws/config` and `~/.kube/config`.
Update these definitions with sops. AWS SSO and other login caches remain
user-managed. Use `aws sso login --profile default --region eu-west-1` to sign
in to the shared work SSO session, and select Kubernetes contexts explicitly
with `kubectl --context CONTEXT ...`.

NuGet's `msp` feed uses AWS's pinned CodeArtifact credential provider, deployed
through Nix into `~/.nuget/plugins/netcore`. It uses the `default-process` profile
to obtain credentials through AWS CLI and the existing SSO session. An additional
user config at `~/.nuget/NuGet/config/msp.config` adds the feed and maps `Msp.*` and
`MovieStarPlanet.*` packages to it. Repository NuGet settings take precedence.
Do not run `aws codeartifact login`; tokens in NuGet config override the provider.

The Framework runs rootless Docker with Compose and Buildx from stable Nixpkgs.
Its socket is `$XDG_RUNTIME_DIR/docker.sock`; new sessions set `DOCKER_HOST`
automatically. Use Docker as your normal user. The shared work ECR registry uses
the stable AWS credential helper with the `default` profile, including when the
calling shell selects a production profile. No `docker login` is needed for ECR.
Activation merges this registry's helper into writable `~/.docker/config.json`,
preserving other registry credentials and settings. Renew an expired SSO session
with `aws sso login --profile default --region eu-west-1`.

OpenVPN 3 uses the stable package and systemd-resolved. The pinned
[DMS OpenVPN plugin](https://github.com/jetersen/dms-openvpn3) provides the bar
control and routes company domains through the DNS servers pushed by the VPN.
Other names use the existing network DNS. Its Python D-Bus dependency is packaged
with the plugin. A polkit rule permits the active local user to update DNS domains
and the default-route flag on numbered VPN interfaces without repeated prompts.

The inline VPN profiles and generated domain list are encrypted as `vpn-profile`,
`vpn-profile-tcp`, and `vpn-domains` in the Framework's sops file. Import profiles
once as the desktop user, then connect from the DMS widget:

```sh
openvpn3 config-import --config /run/secrets/vpn-profile --name moviestarplanet --persistent
openvpn3 config-import --config /run/secrets/vpn-profile-tcp --name moviestarplanet-tcp --persistent
openvpn3 config-manage --config moviestarplanet --dns-scope tunnel
openvpn3 config-manage --config moviestarplanet-tcp --dns-scope tunnel
```

Use `openvpn3 session-auth` if a connection requires interactive authentication.
After replacing an encrypted profile, disconnect and remove its imported copy
before importing the replacement. Refresh `vpn-domains` with the output of
`scripts/export-dns-domains.py` in the `devops-openvpn` repository after its
application definitions change. The plugin reads the list on connection or load;
it has no separate polling service. Browsers must use system DNS for these routes.

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
