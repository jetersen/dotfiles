---
name: niri
description: Guidance for editing niri window manager configuration files under nixos/assets/config/niri/. Use when the task involves niri config, keybinds, gestures, hot corners, layout, window rules, animations, input, displays, or autostart.
user-invocable: false
---

# Niri Window Manager Configuration

This skill provides domain knowledge for editing the niri tiling Wayland compositor config in this dotfiles repo.

## Config Structure

Home Manager generates `~/.config/niri/config.kdl` from `nixos/home/niri.nix`.
Shared KDL files in `nixos/assets/config/niri/cfg/` deploy under
`~/.config/niri/cfg/`. Host modules set preferred workspace outputs and
additional rules. DMS manages its generated files under `~/.config/niri/dms/`.

## KDL Format Patterns

Niri uses [KDL](https://kdl.dev/) for configuration. Common patterns in this config:

- **Spawn commands**: `spawn-at-startup "binary" "arg1" "arg2"` or `spawn-sh-at-startup "shell command"` (the `-sh` variant runs through a shell)
- **Keybinds**: Inside `binds {}`, each line is `Mod+Key { action; }` — optionally with properties like `hotkey-overlay-title="..."`, `allow-when-locked=true`, `cooldown-ms=150`
- **Input**: `input { keyboard { xkb { layout "us,dk" } } touchpad { tap } }`
- **Environment**: `environment { VAR_NAME "value" }` inside `cfg/misc.kdl`
- **Outputs**: `output "NAME" { mode "WxH@rate" scale N }`
- **Commented-out blocks**: Niri uses `/-` before a node to comment out the entire block (not `//`)
- **Comments**: `//` for line comments

## Key Constraints

### Final newlines are mandatory
All KDL files **must** end with a final newline. Niri's config parser may fail to process the last line otherwise. Always verify this when creating or editing files.

### Shell environment
Put settings needed by shell sessions in `nixos/home/shell.nix` as well.

## Niri Wiki Reference

For available configuration options, consult the niri wiki:
- Configuration overview: https://github.com/YaLTeR/niri/wiki/Configuration:-Overview
- Key bindings: https://github.com/YaLTeR/niri/wiki/Configuration:-Key-Bindings
- Input: https://github.com/YaLTeR/niri/wiki/Configuration:-Input
- Outputs: https://github.com/YaLTeR/niri/wiki/Configuration:-Outputs
- Layout: https://github.com/YaLTeR/niri/wiki/Configuration:-Layout
- Window rules: https://github.com/YaLTeR/niri/wiki/Configuration:-Window-Rules
- Miscellaneous: https://github.com/YaLTeR/niri/wiki/Configuration:-Miscellaneous

## Verification

After editing niri config files:

```bash
# Validate the generated configurations for both NixOS hosts
nix build --no-link .#checks.x86_64-linux.desktop-activation
```
