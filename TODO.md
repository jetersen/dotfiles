# NixOS pre-install checklist

The flake is a scaffold, not an installable disk image yet. In particular, every
Disko module is empty, credentials are not declared, and hardware modules contain
a deliberately invalid `NIXOS_ROOT_REPLACE_ME` label. Do not install until the
relevant host section and the shared safety items below are complete.

## Shared decisions and safety

- [ ] Back up each machine and test restoring at least one important file.
- [ ] Confirm `x86_64-linux` for every host; change `hostSpec.system` if needed.
- [ ] Update firmware/BIOS and confirm UEFI boot is enabled.
- [ ] Decide whether Secure Boot is required (for example, with Lanzaboote).
- [ ] Choose the secrets design. Prefer `sops-nix` or `agenix`; never put private
      keys, Wi-Fi PSKs, password hashes, or service tokens directly in the Nix store.
- [ ] Create Joseph's password hash or SSH-only access policy, then decide whether
      to set `users.mutableUsers = false` with encrypted declarative credentials.
- [ ] Add Joseph's SSH public keys before enabling remote-only administration.
- [ ] Decide which Syncthing folders each machine owns and protect against an
      empty machine propagating deletions during first synchronization.
- [ ] Review unfree packages and licenses (`allowUnfree` is currently enabled).
- [ ] Finish classifying the remaining packages in `home/.chezmoidata/packages.toml`
      as shared, desktop-only, work-only, gaming-only, server-only, or intentionally omitted.
- [ ] Choose a secure delivery method for Bitwarden Desktop, Slack, and VS Code.
      Their NixOS 26.05 packages currently depend on EOL Electron releases, so the
      flake deliberately does not permit or install them.
- [ ] Decide which DMS preferences must become declarative. The NixOS module and
      feature dependencies are declared, while DMS's mutable UI settings are not.
- [ ] Review DMS IPC keybindings after the first NixOS login. They are migrated
      from this host into `programs.niri.settings.binds`, while DMS's generated
      KDL remains intentionally excluded from the Nix-native Niri config.
- [ ] Review locale, time zone, US/Danish keyboard switching, and username.
- [ ] Run `nix flake update`, review the input diff, and commit `flake.lock` before
      installation. Continue updating from the `nixos-26.05` release branch.
- [ ] Confirm `linuxPackages_7_1` still evaluates and supports all three devices.

## Disko for each host

Repeat for `rocket`, `framework`, and `karl`:

- [ ] Boot the NixOS 26.05 installer and record `lsblk -o NAME,SIZE,MODEL,SERIAL`.
- [ ] Use stable `/dev/disk/by-id/...` names; never copy `/dev/nvme0n1` blindly.
- [ ] Decide GPT partitions, ESP size, LUKS encryption, filesystem, labels, and swap.
- [ ] Decide whether impermanence, Btrfs subvolumes, snapshots, or ZFS are wanted.
- [ ] For laptops, size swap for hibernation and document the resume setup.
- [ ] Replace `nix/hosts/<host>/disko.nix` with the reviewed `disko.devices` layout.
- [ ] Test the Disko expression against a disposable VM or spare disk first.
- [ ] Generate hardware config in the installer and replace
      `nix/hosts/<host>/hardware-configuration.nix`.

## rocket — desktop and gaming

- [ ] Record CPU, motherboard, network devices, audio devices, and Bluetooth adapter.
- [ ] Identify the exact GPU(s) and add AMD/Intel/NVIDIA configuration as required.
- [ ] If NVIDIA is used, choose the stable driver and verify Niri/Wayland support.
- [ ] Record monitor names/modes with `niri msg outputs`; update `hostSpec.desktop`.
- [ ] Decide whether the 360 Hz display needs a host-specific output block.
- [ ] Validate Steam, Gamescope, GameMode, MangoHud, controllers, and 32-bit graphics.
- [ ] Recreate the rocket-only WirePlumber device override if it is still required.
- [ ] Decide how non-nixpkgs game launchers and Wine prefixes will be managed.

## framework — work and travel laptop

- [ ] Record the exact Framework generation, CPU platform, Wi-Fi card, and display.
- [ ] Confirm the internal display name/mode/scale; update `hostSpec.desktop`.
- [ ] Validate fingerprint reader, ambient light sensor, suspend, hibernate, and resume.
- [ ] Decide whether Framework-specific firmware/fan/battery tools are needed.
- [ ] Review dock monitor names and Kanshi profiles in both docked locations.
- [ ] Confirm required employer VPN, certificates, Slack, development SDKs, and policies.
- [ ] Keep employer secrets and device-management material outside the public flake.

## karl — persistent AI server

- [ ] Record CPU, RAM, NIC, storage topology, and accelerator/GPU model.
- [ ] Decide NVIDIA/AMD/Intel accelerator drivers and container runtime integration.
- [ ] Design a separate persistent location for models, datasets, caches, and outputs.
- [ ] Decide backup, snapshot, retention, UPS, thermal, and power-recovery behavior.
- [ ] Add SSH authorized keys before installation; password SSH is disabled.
- [ ] Decide Tailscale ACL/tags and whether any SSH port is exposed beyond Tailscale.
- [ ] Choose the AI services (for example Ollama or model-serving containers), their
      users, resource limits, health checks, updates, and restart policy.
- [ ] Decide whether Docker is sufficient or rootless Podman is preferable.

## Final validation and installation

- [ ] Format the repository with `nix fmt`.
- [ ] Run `nix flake check`.
- [ ] Evaluate every host with
      `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
- [ ] Build each host from a trusted NixOS machine before touching disks.
- [ ] Review `git diff -- flake.nix flake.lock nix TODO.md` with a second person or pass.
- [ ] Boot the installer, connect networking, clone this repository, and copy in the
      completed hardware configuration without committing secrets.
- [ ] Run Disko only after checking the target disk ID a final time.
- [ ] Install with `nixos-install --flake .#<host>` and set required credentials.
- [ ] Reboot, verify networking/SSH first, then validate desktop or AI services.
- [ ] Keep the installer available until rollback, bootloader, and recovery are tested.
