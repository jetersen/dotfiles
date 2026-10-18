# Dotfiles

The root Nix flake manages Rocket and Framework. Chezmoi manages other Linux,
macOS, Windows, and Codespaces installations from `home/`.

## NixOS layout

- `nixos/hosts/<host>/default.nix` selects profiles, hardware, storage, and host settings.
- `nixos/profiles/` composes the workstation, work, and gaming environments.
- `nixos/modules/` contains system services and reusable options.
- `nixos/home/` contains Home Manager settings. Shells, Starship, DMS, media,
  and desktop defaults have separate modules.
- `nixos/packages/` contains custom packages and release manifests.
- `home/` supplies shared plain assets and shell helpers to both managers.

Framework adds company VPN and credentials, encrypted storage, Secure Boot,
fingerprint support, and roaming DNS. Rocket adds gaming, its existing Btrfs
filesystems, the Windows VM tooling, and Forgejo runner.
NixOS never runs chezmoi. Application profiles, authentication, projects, VM
images, game libraries, and other local state remain outside the Nix store.

## Installation and updates

See [Rocket installation](docs/rocket-install.md) for the CachyOS handover,
backup, preserved disk layout, and recovery. Do not use Disko on Rocket.

Framework uses Disko. Generate `nixos/hosts/framework/hardware-configuration.nix`
on the target with `nixos-generate-config --show-hardware-config --no-filesystems`.
Verify the disk's persistent ID before setting it in `nixos/hosts/framework/disk.nix`.
Its layout is a 2 GiB EFI partition and LUKS containing Btrfs and 72 GiB swap.
The install-time passphrase file is `/tmp/nixos-disk-password` in the live system.
LUKS permits periodic TRIM; changes to discard passthrough take effect when the
encrypted device is opened at boot.

Build the SSH-enabled installer with `nix build .#installer-iso`. Boot in UEFI
mode with Secure Boot disabled and Ethernet connected. It advertises
`framework-installer.local` and permits the SSH key in `nixos/keys/joseph.pub`.
For a standard NixOS ISO, use `scripts/nixos-enable-ssh.sh` from its console.

Framework's Lanzaboote key bundle must be staged at `/var/lib/sbctl` before the
initial bootloader installation, for example with `nixos-anywhere --extra-files`.
Keep an encrypted off-machine backup. Export `keys/db/db.pem` as DER to the EFI
partition, then enroll it through the Framework firmware's Secure Boot DB options
using the owner GUID in `/var/lib/sbctl/GUID`. Retain factory certificates and
revocations. Enable enforcement only after verifying signed boot files.

Build or apply from the checkout:

```sh
nix build .#nixosConfigurations.framework.config.system.build.toplevel
sudo nixos-rebuild switch --flake .#framework
```

Use `rocket` for Rocket. Update inputs with `nix flake update`; do not change
NixOS or Home Manager state versions when updating packages. Hold Space at boot
to select an older generation. Kernel changes require a reboot.

## Desktop and development

Both machines use Niri, DankMaterialShell, DankGreeter, Alacritty, Zed, and Rider.
Systemd-oomd monitors application memory pressure in `app.slice`; the compositor
and session services in `session.slice` remain outside that policy.
Shared Niri bindings live under `home/dot_config/niri/cfg/`; host files select
monitor and workspace preferences. DMS-generated bindings and display settings
remain writable. Super+L locks, Super+D opens the overview, and Super+M focuses
Music Assistant. Framework's display idle timer turns screens off after 15
minutes unless DMS Keep Awake is enabled.

Fish, Bash, Zsh, and PowerShell use Starship and Worktrunk's `wt` shell integration.
Clone helpers enter the newly cloned checkout without writing sidecar files.
Bare and mirror clones leave the current directory unchanged.
`ride` opens a solution or project in Rider. Microfetch runs in interactive
Alacritty shells. Restart shells after configuration changes.

Global development tools are declared in `nixos/home/development.nix`.
Use direnv or project development shells for different toolchain versions:

```sh
nix develop ~/git/dotfiles#python --command fish
```

Other shells are `rust`, `go`, `jvm`, `pulumi`, and `dotnet-preview`.
.NET 10 is the global default; the preview shell sets its own `DOTNET_ROOT`.
Temporary tools can use `nix shell nixpkgs#PACKAGE`.

The gaming profile provides Steam, GE-Proton, Protontricks, and Lutris. Select
GE-Proton per game in Steam. Local VMs use unprivileged QEMU through libvirt and
virt-manager; the standard NAT network autostarts.

Claude, Codex, and T3 Code update through Nix. Claude uses the upstream manifest;
Codex and Zed use the pinned master package set.
Run `nixos/packages/update-claude-code.sh` or `update-t3code.sh VERSION` to update
the corresponding release manifests. Credentials and sessions remain local.
Rocket runs T3 as a lingering user service using `~/.t3`; keep the desktop's
separate local server disabled. The server runs natively with patched Nix library
paths so agent commands inherit the host environment. An older client must not
open newer databases.

## Work access and DNS

The work profile provides OpenVPN 3, its DMS plugin, Storage Monitor, cloud
credentials, Varlock, and private AI instructions. Shared work secrets are in
`nixos/secrets/work.yaml`; Framework's VPN profiles and routing domains are in
`nixos/secrets/framework.yaml`. sops-nix decrypts with the persistent SSH host key.
Never copy private keys or plaintext secrets into Nix expressions.

VPN profiles are imported locally as `moviestarplanet` and `moviestarplanet-tcp`.
The DMS plugin applies their split DNS domains. Framework uses dnsdist at
`127.0.0.2`: home resolvers are preferred over LAN or Tailscale, and public
Cloudflare Security DNS over HTTPS is used only when both home resolvers fail
health checks. Private home, reverse, and known work names never use public
fallback. Work names require their VPN. Recovery returns ordinary queries to
home DNS. MagicDNS is scoped to the tailnet suffix.

Rocket uses LAN routes and the normal systemd-resolved setup; it does not accept
Tailscale subnet routes. Framework accepts those routes for access away from home.
SSH aliases use Tailscale names; additional aliases belong in `~/.ssh/local.config`.
`remote-clip framework` transfers a clipboard image or text. From a work-enabled
machine, `argocd-remote-sso framework --vpn-profile moviestarplanet` uses its
browser for SSO and copies only the selected Argo CD context.

Run `bw login` locally before `workenv COMMAND` loads Varlock work secrets.
Sign in to Proton Pass with `pass-cli login`. Authentication remains local.

## Automatic deployment

Forgejo is primary; its native push mirror updates GitHub for existing chezmoi
installations. All NixOS hosts follow `main` through Comin. CI uses the Kubernetes
runner with Nix sandboxing and a persistent store volume. It builds both systems
and development shells, uploads eligible paths to Attic, checks that `main` still
selects its revision, then notifies the hosts. Outputs of 512 MiB or more stay
out of Attic and may build locally. Lifecycle fetches can see a revision before
CI finishes, so cached output is preferred but not required for deployment.

CI publishes non-retained MQTT update hints over `wss://mqtt.jetersen.dev/socket`
with verified TLS. The `NIXOS_DEPLOY_MQTT_PASSWORD` repository secret authenticates
`nixos-deploy-ci`, which can publish only the two hosts' update topics. Notifications
use QoS 1 and CI waits for broker acknowledgement. Offline hosts check after their
MQTT connection returns.

Both hosts run pc2mqtt with separate SOPS credentials. Each account can publish
only its own state and discovery records, and read its own command topics.
A non-retained `PRESS` on
`<host>/button/update/command` requests a Comin fetch. Broker reconnects also request
a fetch; retained command replays are ignored. Cache reads use each host's
`nix-cache-netrc` SOPS secret. No decryption or Secure Boot private keys are supplied
to CI.

Hosts also check on boot, resume, and NetworkManager events. A stopped or manually
suspended Comin stays paused. To request a check, run
`sudo systemctl start comin-fetch.service`; after a settled evaluation/build
failure, the worker restarts Comin before fetching again. Stop automatic changes
with `sudo systemctl stop comin`. Reverting the running generation alone does not
stop Comin from deploying `main` again. Weekly GC removes unrooted store paths;
retained Comin generations remain protected.

## Chezmoi installation

Install Git, chezmoi, SOPS, age, and Python 3 through the platform package manager.
Linux setup also needs Fish. Clone this repository to `~/git/dotfiles`, then run
`chezmoi --source ~/git/dotfiles/home init`. For a work machine, set
`DOTFILES_WORK=1` before this initialization; personal installations do not
render work secrets.

Run the platform bootstrap explicitly before applying:
`bash home/.chezmoiscripts/linux/.init.sh` or the corresponding macOS script. On Windows,
run `home/.chezmoiscripts/windows/.init.ps1` from built-in Windows PowerShell;
it installs PowerShell 7 and gsudo before the apply phase needs them.

Restore your age identity separately before rendering work files. SOPS uses its
standard age key location or `SOPS_AGE_KEY_FILE`. Shared work settings and private
AI instructions come from `nixos/secrets/work.yaml`; ordinary source reads never
log in to Proton Pass. Edit encrypted values with SOPS. Enroll an additional
work host by adding its age recipient and running `sops updatekeys` for that file;
Rocket is not currently a work-secret recipient.

Restore an SSH key and its matching `.pub` explicitly with
`python3 home/.chezmoiscripts/.init-ssh.py /path/to/backup-key`. The importer
refuses to overwrite existing keys. Review `chezmoi diff`, then run `chezmoi apply`.
Application installation scripts can change system settings. Subsequent updates
use `chezmoi update`.
