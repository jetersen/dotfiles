# My dotfiles

NixOS uses the root Nix flake and configuration under `nixos/`.
Other Linux distributions, macOS, and Windows use [chezmoi](https://www.chezmoi.io/)
with `home/` as its source root.

NixOS composes the ordinary desktop and development environment through the
`workstation` profile. The optional `work` profile adds company VPN, credentials,
AI work instructions, and the DMS storage widget; Framework imports it explicitly.
The optional `gaming` profile enables NixOS Steam integration and installs Lutris,
Protontricks, and GE-Proton. Game libraries and Wine prefixes remain local data.
Profile composition
lives under `nixos/profiles/`, reusable system modules under `nixos/modules/`,
and user applications and settings under `nixos/home/`.

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

The reusable `nixosModules.workstation` profile provides the desktop, development
tools, rootless containers, Home Manager, and GitOps deployment. Each
host supplies its own hardware, storage, password and sops file. Framework's
panel scaling, battery prompt, kernel and fingerprint sleep workaround stay in
its host directory. Rocket has its own generated hardware, preserved-filesystem layout, and secrets.
Its personal base excludes the optional work profile; automatic deployment stays
disabled until migration is complete.

The Framework configuration uses Niri, DankMaterialShell, DankGreeter, Disko,
and sops-nix.

Alacritty shell startup runs a patched Microfetch with workstation hardware,
display, battery, network, appearance, and Nix package information. Build or run
it with `nix build .#microfetch` or `nix run .#microfetch`. The local Rust extensions
and upstream patch live in `nixos/packages/microfetch/`. Display names include EDID
model IDs, and the card reports the Alacritty font and days since June 7, 2024.
Package counts are cached under `$XDG_CACHE_HOME/microfetch` (default
`~/.cache/microfetch`) and refreshed when a profile's resolved Nix store target
changes; unchanged profiles require no Nix subprocess.

The initial desktop includes only essential applications from NixOS stable.
DMS and DankGreeter use their upstream flakes pinned to release tags, with
stable nixpkgs.
Zen is pinned separately because it is not available in the stable package set.
Slack, Discord, Zed, .NET 10, AWS CLI, kubectl, and Google Cloud CLI use stable
packages. Google Cloud CLI includes the GKE authentication plugin for kubectl.
Zed uses the packaged FHS wrapper for downloaded language servers, with C#,
Nix, and PowerShell extensions and the DMS theme. Its shared preferences come
from `home/dot_config/zed/private_settings.json`, with Nix-specific overrides.
It handles plain text and JSON files; the
terminal editor remains Neovim.

Claude Code uses Anthropic's upstream release manifest with stable Nixpkgs'
native packaging. Run `nixos/packages/update-claude-code.sh` to pin the latest
release, or pass a specific version. Review the manifest diff and rebuild NixOS;
Nix verifies the binary against the manifest's checksum.
Codex CLI uses a separate pinned `nixpkgs-master` input to receive updates before
they reach the unstable channel. Renovate maintains its lock; update it manually
with `nix flake update nixpkgs-master`. CodeGraph uses `nixpkgs-unstable`.
Rebuild NixOS after changing either pin.
T3 Code's desktop and standalone CLI use the same checksum-pinned upstream
release from `nixos/packages/workstation-manifest.json`. Run
`nixos/packages/update-t3code.sh VERSION` to update both artifacts. Nix provides
their Linux runtime; automatic application updates are disabled. T3 Code includes
both provider CLIs on its runtime path, using the same provider
versions as the terminal. Launch `claude`, `codex`, or `t3code-desktop`; `t3` runs
the web interface. Sign in locally with `claude auth login` and `codex login`.
Credentials and application state remain user-managed outside the Nix store.
Application binaries update through Nix rather than their own installers.

Development and infrastructure tools are declared in
`nixos/home/development.nix`. Node.js includes npm; Python packages and virtual
environments use `uv`. Stable Go, Rust (Cargo, rustfmt, and Clippy), Bun, and
Java 21 with Maven are available globally. A C compiler and pkg-config support
native builds. PowerShell is available as `pwsh`.

Use project development shells through direnv for project-specific versions and
native libraries. A shell can live outside the project, for example in a
personal flake, and `nix develop /path/to/that/flake#shell-name` works from the
project directory. For a temporary tool, use `nix shell nixpkgs#PACKAGE`.
Neither approach requires committing Nix files to the project.

Named shells in this flake provide Python (`ruff`, Pyright, debugpy), Rust
(Cargo audit, bloat, machete, nextest, Trunk), Go (golangci-lint), JVM (Java 21,
Maven, Gradle), and Pulumi provider tools (pulumictl, schema-tools,
upgrade-provider). From any project, run:

```sh
nix develop ~/git/dotfiles#python --command fish
```

Replace `python` with `rust`, `go`, `jvm`, `pulumi`, or `dotnet-preview`.
The preview shell uses the pinned unstable .NET 11 SDK and overrides `DOTNET_ROOT`
for that session; .NET 10 remains the global default. CI builds these shells and
publishes their eligible outputs to Attic using the same size policy as NixOS.


Fish, Bash, Zsh, and PowerShell share Docker aliases, clone-and-enter helpers,
`cws`, `ride`, `open`, `dotenv`, and the existing development shortcuts.
`ride` opens a solution or project in stable Rider. PowerShell's `posh-git`,
`cd-extras`, and `Get-ChildItemColor` modules use pinned upstream sources;
profiles never install modules at startup. Direnv integrates with all four shells.

Fish, Bash, Zsh, and PowerShell use the same compact Starship layout. Identity
appears in remote or changed-user sessions; Framework's battery percentage
appears when unplugged. Fastfetch runs in interactive Alacritty shells. Start a
new shell after a configuration update.
Vite Plus (`vp`), topf, Freelens, and Varlock use checksum-pinned upstream releases in
`nixos/packages/workstation-manifest.json`; Renovate updates both versions and
checksums. Vite Plus and Freelens use FHS wrappers for upstream runtime binaries.
Vite Plus prefers Nix-provided Node.js and package managers; its project tooling
and caches remain writable user state. Mosh accepts incoming UDP sessions over
Tailscale only, using ports 60000–61000.

ILSpy, dotnet-outdated, database clients, diagnostic tools, DBeaver Community,
Charles, and Remmina use stable packages. VictoriaLogs queries use `vlogscli`;
its package builds only the CLI. LocalSend enables its TCP/UDP discovery and
transfer port through the NixOS module.
CSharpier uses the stable Nixpkgs package. Lambda Tools, dotnet-script,
`central-pkg-converter`, `apicompat`, and the .NET counters, trace, and stack tools
use official NuGet archives pinned in the flake. Renovate updates their URLs
and lock-file hashes. They work without a mutable global tool installation.
Snitch builds the pinned integration branch from `jetersen/snitch`; its NuGet
dependencies are locked in `nixos/packages/snitch-deps.json`.

NixOS and chezmoi share personal Niri bindings from
`home/dot_config/niri/cfg/keybinds.kdl`, included after DMS defaults.
Workspace output preferences live in each host's `dotfiles.niri.workspaceOutputs`.
Framework reuses the work dock's monitor serials; undocked sessions fall back to
available outputs. Slack and Discord share the `chat` workspace. Shared floating
and routing rules under `home/dot_config/niri/cfg/` serve both Chezmoi and NixOS.
Framework starts Slack natively on Wayland. Its Nixpkgs launcher enables PipeWire
capture, and Niri uses the GNOME ScreenCast portal; verify sharing in a Slack
huddle after deployment.

The gaming profile exposes the checksum-pinned upstream release as `GE-Proton`
in Steam compatibility settings. Select it for the desired games and restart
Steam after configuration updates; the selection name stays stable across releases. Renovate tracks its release and checksum in
`nixos/packages/workstation-manifest.json`; updates arrive with configuration
updates. CI builds the pinned compatibility tool before merging dependency
updates. ProtonUp-Qt is not needed. The profile also adds the Battle.net helper-window
workaround. `nixos/hosts/rocket/desktop.nix` contains Rocket's desktop choices;
its hardware and storage configuration live alongside it. Input-remapper is available
on Rocket but starts only on request, with no tracked presets or autoload rules.

Super+L locks, Super+D opens the overview, and Super+M opens or focuses Music Assistant;
Ctrl+Alt+Delete opens the task manager. Music Assistant and Pear Desktop open on
the dedicated `music` workspace.

Music Assistant companion uses software volume on framework, rocket, and worklaptop
so its application volume stays independent of system volume. Home Manager and
chezmoi merge this preference into the writable settings file, preserving player
identity, software volume, mute, and other local settings. Restart the companion
after applying the preference if it is already running.

Pear Desktop provides YouTube Music; `youtube-music` focuses or opens it.
Home activation enables its tray, video hiding, Discord integration, and shortcut
plugin while preserving local state and other preferences. Pear starts hidden
in the tray. Its remote-control API and built-in updater are disabled; Nix
manages application updates.
Pear's local resume option is disabled so YouTube Music can restore the latest
queue from another device. On Android, enable **Continue listening on connected
devices** under YouTube Music's playback settings. Pause the source player, then
open or refresh the destination player; playback position may restart at zero.
GTK3 apps use adw-gtk3 with DMS-generated colors, including virt-manager.
TinyRDM, RustDesk, and Rider use stable packages. Dolphin opens PDFs in Zen,
images in Gwenview, videos in MPV, and archives in Ark. KDE's archive service
menus, archive browsing, and image/PDF/video thumbnail plugins are installed.

Local VMs use virt-manager with QEMU/KVM and libvirt (`qemu:///system`).
QEMU runs unprivileged; UEFI firmware, a software TPM, virtiofs shared folders,
and SPICE USB redirection are available. The standard `default` NAT network
autostarts. VM definitions and disks remain local state under `/var/lib/libvirt`.

SSH aliases `rocket`, `framework`, `worklaptop`, and `truenasadmin` use Tailscale hostnames.
The NAS alias logs in as `truenas_admin`; its host key is pinned. Keep additional
machine-local aliases in `~/.ssh/local.config`.

On Linux Wayland desktops, `remote-clip framework` fetches an image or plain text
and copies it locally. It prefers images when both types are offered; use
`--type text` to request text. Captures use private files under the runtime
directory (or a private temporary directory). Use `-o FILE` to keep a copy,
`-o -` for raw stdout, or `--no-copy` to save without changing the local clipboard.
Both machines need Python 3, systemd user sessions, and wl-clipboard.

`argocd-remote-sso framework --vpn-profile moviestarplanet` logs in through
Framework's browser and merges only the selected context locally. It uses
Framework's current context to choose the server; pass `--server HOSTNAME` for
an initial login, `--context NAME` to select a named context, or `--copy-only`
to reuse a login. On CachyOS, use the actual local VPN profile, such as `work`.
The remote desktop needs Argo CD, Python 3, and Mike Farah yq v4; the local
machine needs Python 3, yq v4, and OpenVPN 3. Nix deploys this helper with the
work profile. Unrelated local contexts are preserved; incompatible shared server
settings require a separate `--config` file.

These helpers transfer directly over Tailscale SSH, which verifies the remote
host key through the tailnet. They require an authenticated Tailscale client and
an SSH policy permitting the connection. Clipboard transfers have a 30-second
limit; remote browser login allows four minutes. They replace the old
`worklaptop-clip` and `argocd-worklaptop-sso` commands and work with either desktop
as the remote host.

The private npm registry configuration and Varlock work schema are deployed by
sops-nix. Run `bw login` once in a local terminal, then use
`workenv COMMAND [ARGUMENTS...]` to load work secrets through Varlock. Varlock
handles subsequent Bitwarden unlock prompts and session caching according to
the schema. Bitwarden CLI authentication stays local to each machine.

`gh stack` uses unstable's current GitHub CLI extension to match its upstream
skill. `git-dirty` reuses the shared script in `home/dot_local/bin/`.
Git aliases are shared by chezmoi and Nix through `home/dot_config/git/aliases`;
the `home` and `work` aliases use each configuration's email identities.
Claude and Codex share pinned skills through `~/.agents/skills` and
`~/.claude/skills`. Common instructions come from
`home/.chezmoitemplates/ai-instructions.md`; chezmoi adds the private work section
from the shared encrypted `nixos/secrets/work.yaml`. NixOS assembles it with sops-nix at runtime, outside the Nix
store, and links both clients to the same file. Skills become available in a new
agent session. Built-in client skills and cloud-synced Claude skills remain
managed by their clients.
Home activation configures CodeGraph and the VictoriaLogs HTTP MCP server for
Claude and Codex while preserving their other settings. The VictoriaLogs endpoint
is deployed through sops-nix. New agent sessions load the servers; run `codegraph init --yes` in a project to create its local index.

Proton Pass CLI is available as `pass-cli`. Sign in interactively with
`pass-cli login` in a local terminal.

Forgejo is the primary repository at `forgejo.jetersen.dev/jetersen/dotfiles`.
The GitHub repository remains a push mirror for existing chezmoi installations;
Forgejo's native push mirror sends `main` and tags on push using a deploy key
limited to that GitHub repository. No mirror workflow is needed.

The homelab's shared Renovate job updates both repositories. Nix dependency PRs,
including Claude's upstream manifest, pinned release tags, and lock maintenance,
merge automatically with a linear history once the required
`NixOS / framework (pull_request)` check passes. The PR must be up to date with
`main`; rejected reviews block merging. Other dotfiles updates need manual merging.

NixOS CI builds Framework, Rocket, and named project shells on Rocket. A persistent Docker volume retains
the Nix store and fetched inputs for reuse across disposable jobs. Builds run
in a serialized job to share the store safely. CI tools include Nix from the locked
`nixpkgs-master` input. Both hosts' build plans evaluate in parallel with separate
persistent evaluation caches, then one build invocation realizes their shared
graph under the same build budget. CI respects derivations that request local
building instead of cache lookups. Command timings separate evaluation,
realization, and publication costs. The shared job image's Nix bootstraps the CI
tools; no separate Nix container or preparation job is needed. Nix reclaims
unrooted paths under disk pressure; the latest systems and CI tools stay rooted.
CI substitutes missing paths from the public NixOS cache and private Attic cache.
CI imports available public-cache signatures before uploading system outputs to
private Attic. Attic skips paths signed by the public NixOS cache, and CI excludes
outputs at or above `ATTIC_MAX_NAR_MIB` in the workflow
(currently 512 MiB unpacked). This applies to every package, not just vendor
repacks. Hosts download and package or compile excluded outputs locally when
needed. CI retains them in its working store. CI then sends an SSH notification over Tailscale. Stock Comin fetches `main`
and builds and applies the latest revision. A boot, resume, or network check can
see a newer revision before CI finishes, in which case missing outputs build
locally. A failed build leaves the running generation intact. Every NixOS host follows `main`, including
future hosts. The notification key can only request a fetch;
it cannot select a revision or run arbitrary commands. The laptop also checks
on boot, resume, and NetworkManager connection events, so offline machines catch
up when they return. There are no periodic deployment checks. If a notification
is missed while the laptop stays connected, the next lifecycle event or
`sudo systemctl start comin-fetch.service` checks for the latest published revision.
Comin prefers cached outputs and allows one local packaging or build job using
up to four cores. Missing cache entries can therefore build locally. Nix does not
retain negative cache lookups, so
newly published paths are immediately available. One local systemd unit handles
SSH notifications and lifecycle events. It restarts an idle Comin after a failed
evaluation or build before fetching again; active work defers a requested retry until it settles. Manual suspension and a
stopped daemon end the retry chain. The notification account can only start that unit
through a narrowly scoped sudo rule. Interactive Nix commands can still build
normally.

CI requires an up-to-date lock file and does not receive the laptop's decryption
or Secure Boot private keys. Kernel changes still require a reboot to take effect.

The CI-only `NIXOS_DEPLOY_NOTIFY_KEY` matches `nixos/keys/deploy-notify.pub`.
The `FRAMEWORK_HOST` repository variable selects its fully qualified Tailscale
hostname. SSH verifies Framework's host key against `nixos/keys/framework-host.pub`.
Cache access uses the encrypted `nix-cache-netrc` secret and the public signing
key declared in `nixos/modules/gitops.nix`. Keep prior boot generations for
rollback. Weekly garbage collection removes unrooted store paths; Comin's retained
rollback generations stay protected. Store optimisation also runs automatically.
The boot menu is hidden; hold Space during startup to choose another
generation. To stop automatic updates while diagnosing a problem, run
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
`nixos/secrets/work.yaml` as `aws-config` and `kube-config`. Home Manager
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

Tailscale accepts the homelab's advertised host routes for access away from the
LAN. Each workstation using CloudConnexa also needs the VPN coexistence exception
in the [tailnet policy](https://github.com/jetersen/tailscale-acls#openvpn-coexistence)
so Tailscale passes VPN replies to the host firewall.

The inline VPN profiles and generated domain list are encrypted as `vpn-profile`,
`vpn-profile-tcp`, and `vpn-domains` in `nixos/secrets/work.yaml`. Import profiles
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

Nix downloads the wallpaper from an external collection at a pinned revision and
verifies its checksum. Wallpaper binaries are not stored in this repository.
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
and `home.stateVersion` unchanged when updating packages. Shared NixOS modules and Home Manager serve both hosts.

## Rocket migration

See [the backup, installation, and restore procedure](docs/rocket-install.md)
and [the home and AI state handover](docs/rocket-home.md).

Rocket uses new Btrfs subvolumes `@nixos`, `@nixos-nix`, and `@nixos-snapshots`
on its existing OS filesystem. Keep the CachyOS root and snapshots, reuse
`@home` and `@srv`, and mount the existing games filesystem and Steam bind mount.
Do not run Disko or format either disk. Verify persistent disk IDs and filesystem
UUIDs against `nixos/hosts/rocket/filesystems.nix` from the live installer first.
Keep independent backups before changing boot files or mounting preserved data.

Stage the existing SSH host key securely, matching `nixos/keys/rocket-host.pub`,
so sops-nix can decrypt Rocket's host secrets. Preserve Tailscale enrollment,
libvirt definitions, VM disks, UEFI variables, and TPM state. Restore VM files
with ownership appropriate for NixOS's unprivileged QEMU. Restore the private
`/etc/pc2mqtt/config.json` with mode 0600 to retain device identity and MQTT login;
the service loads it as a systemd credential outside the Nix store.

Use a fresh host Docker data root. Preserve only the managed runner's
`homelab-forgejo-runner_runner-data` and `homelab-forgejo-runner_docker-cache`
volumes and registration; recreate disposable test environments. Do not transplant
old host Docker/containerd metadata into a different engine version. The runner
uses the Compose configuration in `~/git/homelab/infrastructure/forgejo/runner/`,
with registration under `~/.local/state/forgejo-runner/registration`. Create
`/var/lib/forgejo-runner/migration-ready` only after restoring and verifying these
files and volumes. Compose recreates the NFS cache mount.

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
