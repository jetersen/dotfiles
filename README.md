# Dotfiles

NixOS and Home Manager configuration for my workstations.

## Installation

Use the [host configuration](nixos/hosts/) for hardware and storage settings.
Verify disk IDs before running Disko. For systems that reuse existing
partitions, follow the [storage and recovery guide](docs/rocket-recovery.md).

To build a configuration locally, replace `HOST` with its flake configuration name:

```sh
nix build .#nixosConfigurations.HOST.config.system.build.toplevel
```

## Desktop and development

The desktop uses Niri and Dux. Shared shortcuts live in the
[Niri configuration](nixos/assets/config/niri/cfg/keybinds.kdl).
Run `unlock-keyring` from a terminal if an app needs stored credentials.

[Home Manager](nixos/home/development.nix) defines the global development tools.
Use direnv or a Nix development shell for project-specific toolchains:

```sh
nix develop .#python
```

Home Manager shares [agent skills](nixos/assets/skills) between Codex and Claude,
including vendored skills from
[Theo's tstack](https://github.com/t3dotgg/tstack/tree/1085050f3baed1ac724caa4a8166145fb2ac88af/skills).

## Automatic deployment

Hosts follow Forgejo's `main` branch. CI tests and builds each revision,
publishes missing build outputs to Attic, and notifies the hosts once the
revision is ready.

Each host resolves and pins a revision before upgrading. It switches only when
the required binaries are available in the configured caches. If they are
missing, the current system keeps running and a later check can retry. Upgrades
leave rebooting to the operator and retain local generations for rollback.

To check for an update manually, run `sudo systemctl start nixos-upgrade.service`.
View the result with `journalctl -u nixos-upgrade.service`.
