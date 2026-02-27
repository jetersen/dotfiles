---
name: niri
description: Guidance for editing niri window manager configuration files under home/dot_config/niri/. Use when the task involves niri config, keybinds, gestures, hot corners, layout, window rules, animations, input, displays, or autostart.
user-invocable: false
---

# Niri Window Manager Configuration

This skill provides domain knowledge for editing the niri tiling Wayland compositor config in this dotfiles repo.

## Config Structure

The niri config lives in `home/dot_config/niri/` and deploys to `~/.config/niri/`. The main entry point is `config.kdl`, which includes all other files:

| Source file | Deploys as | Purpose |
|---|---|---|
| `config.kdl` | `~/.config/niri/config.kdl` | Entry point — only `include` directives |
| `noctalia.kdl` | `~/.config/niri/noctalia.kdl` | Noctalia theme colors (focus-ring, border, shadow, tab-indicator) |
| `cfg/animation.kdl` | `~/.config/niri/cfg/animation.kdl` | Animation settings (currently off) |
| `cfg/autostart.kdl.tmpl` | `~/.config/niri/cfg/autostart.kdl` | Startup applications — **chezmoi template** |
| `cfg/decorations.kdl` | `~/.config/niri/cfg/decorations.kdl` | Window decorations (focus-ring, border, shadow — all off, overridden by theme) |
| `cfg/display.kdl` | `~/.config/niri/cfg/display.kdl` | Monitor/output configuration |
| `cfg/input.kdl` | `~/.config/niri/cfg/input.kdl` | Keyboard layout, touchpad, focus behavior |
| `cfg/keybinds.kdl` | `~/.config/niri/cfg/keybinds.kdl` | All key bindings inside a `binds {}` block |
| `cfg/layout.kdl` | `~/.config/niri/cfg/layout.kdl` | Layout gaps, preset column widths, centering |
| `cfg/misc.kdl` | `~/.config/niri/cfg/misc.kdl` | Environment variables, CSD preference, screenshots, hotkey overlay |
| `cfg/rules.kdl` | `~/.config/niri/cfg/rules.kdl` | Window and layer rules |

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

### chezmoi template: `autostart.kdl.tmpl`
This file uses Go template syntax (`{{ if .isWork }}...{{ end }}`). The `.tmpl` suffix tells chezmoi to process it. The rendered output drops the `.tmpl` extension. Use chezmoi template variables (e.g. `.isWork`) for conditional blocks.

### Environment variables may need shell config sync
If you add or change environment variables in `cfg/misc.kdl`'s `environment {}` block that should also be available in shell sessions, you must update all three shell configs per the CLAUDE.md sync rules:
- `home/dot_bashrc`
- `home/dot_config/fish/conf.d/config.fish`
- `home/dot_config/powershell/Microsoft.PowerShell_profile.ps1`

### Platform filtering
Niri configs only deploy when `.isNiri` is true in chezmoi data (see `home/.chezmoiignore.tmpl`). The entire `dot_config/niri` directory is ignored on non-niri systems.

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
# Validate the niri config (checks deployed config at ~/.config/niri/)
niri validate

# Preview what chezmoi will deploy (useful for template files)
chezmoi diff
```
