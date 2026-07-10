# My dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

This repository has two complementary configuration paths:

- `flake.nix` and `nix/` declaratively manage NixOS machines.
- `home/` remains the chezmoi source for macOS, Windows, and non-NixOS Linux.

The initial NixOS hosts are `rocket` (desktop/gaming), `framework` (work/travel
laptop), and `karl` (headless persistent AI server). They share stable NixOS
26.05 modules and Linux 7.1 while keeping hardware and disk layouts per host.
Niri itself comes from nixpkgs stable; `niri-flake` is used only for its typed,
Nix-native Home Manager configuration and validation module.

Before attempting an installation, complete [TODO.md](TODO.md). The Disko and
hardware modules are intentionally placeholders.

Useful NixOS commands from the repository root:

```sh
nix fmt
nix flake check
sudo nixos-rebuild switch --flake .#rocket
```

## Install

### Linux / macOS

```sh
sh -c "$(curl -fsLS get.chezmoi.io/lb)" -- init --apply jetersen
```

### Windows

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force;
iex "&{$(irm 'https://get.chezmoi.io/ps1')} init --apply jetersen"
```

## Update

```sh
chezmoi update
```
