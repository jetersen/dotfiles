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

Btrfs scrubbing runs monthly on AC power, capped at 100 MiB/s per device.
Subvolumes sharing a filesystem are scrubbed once. Runs skipped on battery wait
until the next scheduled occurrence. Inspect results with `sudo btrfs scrub status /`;
Rocket's games filesystem can be checked with `sudo btrfs scrub status /media/games`.

## Desktop and development

Both machines use Niri, Dux Shell, Dux Greeter, Alacritty, Zed, and Rider.
Dux Files handles folders, archives, file-manager shortcuts and portal open/save
dialogs. Dolphin and Ark remain available as fallbacks.
Systemd-oomd monitors application memory pressure in `app.slice`; the compositor
and session services in `session.slice` remain outside that policy.
Shared Niri bindings live under `home/dot_config/niri/cfg/`; host files select
monitor and workspace preferences. DMS-generated bindings and display settings
remain writable. Super+L locks, Super+D opens the overview, and Super+M focuses
Music Assistant. Framework's display idle timer turns screens off after 15
minutes unless DMS Keep Awake is enabled.
Framework's DMS profiles match the work monitors by serial number, across USB-C
ports. The work dock uses both Dell monitors with the laptop panel disabled;
undocking restores the panel at 150% scale. Other display layouts remain local.

Fish, Bash, Zsh, and PowerShell use Starship and Worktrunk's `wt` shell integration.
Clone helpers enter the newly cloned checkout without writing sidecar files.
Bare and mirror clones leave the current directory unchanged.
`ride` opens a solution or project in Rider. Microfetch runs in interactive
Alacritty shells. Restart shells after configuration changes.

Global development tools are declared in `nixos/home/development.nix`.
Aspire uses the official Nix packaging with a separately pinned CLI release archive.
Its extracted Linux bundles use `nix-ld`; keep `~/.aspire/bin` out of the NixOS
session PATH so older manual installs cannot mask the managed CLI. Restart the
desktop session after switching to this setup.
Use direnv or project development shells for different toolchain versions:

```sh
nix develop ~/git/dotfiles#python --command fish
```

Other shells are `rust`, `go`, `jvm`, `pulumi`, and `dotnet-preview`.
.NET 10 is the global default; the preview shell sets its own `DOTNET_ROOT`.
Temporary tools can use `nix shell nixpkgs#PACKAGE` or comma, for example
`, dig example.com`. Bash, Zsh, and Fish suggest packages for missing commands.
The pinned nix-index database covers executables only and needs no local indexing;
use `nix-locate bin/COMMAND` to search it.

The gaming profile provides Steam, GE-Proton, Protontricks, and Lutris. Select
GE-Proton per game in Steam. Local VMs use unprivileged QEMU through libvirt and
virt-manager; the standard NAT network autostarts.

Claude, Codex, and T3 Code update through Nix. Renovate updates Claude and T3's
upstream versions and Linux artifact hashes; Claude's manifest stores only the
version and x86_64 Linux checksum. Codex and Zed use the pinned master package set.
For manual updates, run `nixos/packages/update-claude-code.sh [VERSION]` or
`nixos/packages/update-t3code.sh VERSION`, then push for CI deployment.
Credentials and sessions remain local.
Both hosts let `joseph` manage Tailscale Serve. On Framework, enable Tailscale HTTPS
in T3's connection settings and relaunch the desktop app to use its MagicDNS HTTPS URL.
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

Storage Monitor includes Python and util-linux for read-only monitoring of mounted
filesystems, including LUKS and LVM. Optional UDisks metadata uses busctl. Disk
actions remain disabled without PyGObject; system and nested layouts are monitor-only.

VPN profiles are imported locally as `moviestarplanet` and `moviestarplanet-tcp`.
The DMS plugin applies their split DNS domains. Framework uses dnsdist at
`127.0.0.2`: home resolvers are preferred over LAN or Tailscale, and public
Cloudflare Security DNS over HTTPS is used only when both home resolvers fail
health checks. Private home and reverse names never use public fallback.
Work domains use VPN DNS while connected and ordinary resolution when
disconnected. MagicDNS is scoped to the tailnet suffix.

Rocket uses LAN routes and the normal systemd-resolved setup; it does not accept
Tailscale subnet routes. Framework accepts those routes for access away from home.
SSH aliases use Tailscale names; additional aliases belong in `~/.ssh/local.config`.
`remote-clip framework` transfers a clipboard image or text. From a work-enabled
machine, `argocd-remote-sso framework --vpn-profile moviestarplanet` uses its
browser for SSO and copies only the selected Argo CD context.

On NixOS, `wl-copy` and `wl-paste` use the host's logged-in Wayland desktop,
including over SSH or mosh. They recover missing display variables from the
user service manager; a running desktop session is required. They access the
remote host's clipboard, not the connecting computer's. Run `remote-clip rocket`
on the connecting Linux desktop to fetch Rocket's clipboard, including images.
For text sent to the connecting terminal's clipboard, OSC 52 depends on terminal
and transport support. Terminal paste sends local clipboard text as keyboard
input; SSH and mosh do not forward a Wayland clipboard.

Both NixOS hosts provide Varlock, the Bitwarden CLI, and the work schema from
`nixos/secrets/varlock.yaml`, independently of the full work profile.
Run `bw login` once on each machine, then unlock interactively with
`varlock load -p ~/.config/varlock/work/.env.schema`. Varlock prompts for the
Bitwarden master password and caches the session for the schema's session TTL.
Use `workenv COMMAND` to inject the resolved variables, including `TEAMCITY_URL`
and `TEAMCITY_TOKEN`, into a command. Bare `varlock load` uses the current
directory's schema, so pass the work schema path explicitly.
Sign in to Proton Pass with `pass-cli login`. Authentication remains local.

## Automatic deployment

Forgejo is primary; its native push mirror updates GitHub for existing chezmoi
installations. All NixOS hosts follow `main` through Comin. Lightweight Python
checks run on Kubernetes before full Nix builds run on either Docker pool with
sandboxing and a persistent store volume. CI builds both systems
and development shells, uploads eligible paths to Attic, checks that `main` still
selects its revision, then notifies the hosts. Outputs of 512 MiB or more stay
out of Attic and may build locally. Lifecycle fetches can see a revision before
CI finishes, so cached output is preferred but not required for deployment.

CI plans Framework, dynamically discovered checks, Rust dependencies, development
shells and both Proton outputs alongside a separate Rocket planner. The two native
planners use separate persistent evaluation caches. Once both succeed, CI roots
the selected derivations and realizes their shared graph in one build, then validates
every selected output before publishing or notifying hosts.
Compilation is serialized with four cores per build to bound peak memory demand.
The shared workflow concurrency group permits one Nix CI run across both pools;
an offline runner does not prevent the other pool from claiming queued builds.

CI runs `checks.x86_64-linux` before publishing or notifying hosts. Run the same
groups locally with `nix flake check --no-update-lock-file --max-jobs 2 --cores 4`,
or select one with `nix build .#checks.x86_64-linux.dns-routing`:

- `desktop-activation` exercises both hosts' production DMS configurators, settings
  and plugin preservation, GTK integration and full Niri configuration validation.
  The Framework idle check tests state logic in the patched QML source.
- `dns-routing` runs real dnsdist with loopback DNS and verified TLS DoH fixtures,
  checking routing, fail-closed behavior, backend restart recovery and fallback TTL.
- `tooling-unit` runs the CI orchestration, package updater and Wayland clipboard
  unit suites.
- `module-contracts` checks selected evaluated service and credential properties.
- `native-comin` and `native-pc2mqtt` reuse the tested packages built for the systems.

These checks use sandboxed derivations with narrow source inputs. CI roots their
outputs and publishes eligible paths to Attic; unchanged checks can substitute.
`nix flake check --no-build` only evaluates and does not execute these tests.
There are no VM prerequisites. Boot, systemd ordering/credentials/restarts, live
Wayland/QML behavior and tunnel/interface/source-address transitions remain outside
this coverage. Backend process restart tests do not cover interface transitions.

CI publishes non-retained MQTT update hints over `wss://mqtt.jetersen.dev/socket`
with verified TLS. The `NIXOS_DEPLOY_MQTT_PASSWORD` repository secret authenticates
`nixos-deploy-ci`, which can publish only the two hosts' update topics. Notifications
use QoS 1 and CI waits for broker acknowledgement. Offline hosts check after their
MQTT connection returns. Crane caches pc2mqtt's compiled Rust dependencies separately
from its source. CI retains the latest dependency artifacts and publishes eligible
outputs to Attic for reuse across source edits; dependency and toolchain changes
rebuild them.

Both hosts run pc2mqtt with separate SOPS credentials. Each account can publish
only its own state and discovery records, and read its own command topics.
A non-retained `PRESS` on
`<host>/button/update/command` queues a Comin fetch in pc2mqtt. Idle Comin fetches
through its local gRPC socket; busy, stopped, or suspended Comin leaves the request
pending. Comin events wake the single update worker without readiness polling. MQTT
commands stay queued until the fetched generation is active or Comin has staged
a boot-only deployment. If an older generation is running, pc2mqtt resubmits the
selected deployment while preserving suspension and reboot-only inhibitors.
Broker reconnects also request an update; retained command replays are ignored.
Home Assistant discovers Deployment, Deployed revision, and Reboot required entities
on each pc2mqtt device. Deployment
attributes include the booted revision; state changes come from Comin events.
Cache reads use each host's
`nix-cache-netrc` SOPS secret. No decryption or Secure Boot private keys are supplied
to CI.

Hosts also check on boot, resume, NetworkManager events, and Comin socket changes
through a systemd path watch. A stopped or manually suspended Comin stays paused. To request a check, run
`sudo systemctl start comin-fetch.service`, which queues the same pc2mqtt request
without a retry timer. After a settled evaluation/build failure, pc2mqtt restarts
the active Comin daemon before fetching again. Stop automatic changes
with `sudo systemctl stop comin`. Reverting the running generation alone does not
stop Comin from deploying `main` again. Weekly GC removes unrooted store paths;
retained Comin generations remain protected.

Comin is pinned to the Forgejo fork's `dotfiles-v0.14` branch, which carries the
deployment, rewritten-main and reboot-notification fixes with native Go tests.
Keep dotfiles `main` linear. Both hosts opt into rewritten-main support through
`COMIN_ALLOW_REWRITTEN_MAIN=1`: updates follow the configured `main` tip even after
an amend, rebase, or force push. Testing branches still have to descend from main,
and suspension and deployment inhibitors still apply. pc2mqtt reports branch
selection errors as failures and retains the queued request for a later retry.

Both desktops show a notification when an update requires a reboot. The session
listener also checks at login, avoids duplicate notices for the same deployment,
and reconnects when Comin restarts. Routine deployment progress stays silent.

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
