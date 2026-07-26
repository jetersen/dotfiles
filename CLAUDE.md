# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Cross-platform dotfiles repository managing configurations for Fish, PowerShell, Git, SSH, and Oh My Posh. Targets Linux (CachyOS), macOS, Windows, and GitHub Codespaces. Managed with [chezmoi](https://www.chezmoi.io/).

## Git Workflow

Work directly on `main` by default. Do not create a branch or worktree unless the user explicitly asks for one.

## Build & Deploy

Dotfiles are deployed via chezmoi — a single static binary with no dependencies.

```bash
# Install and apply all dotfiles
chezmoi init --apply jetersen

# Preview changes without applying
chezmoi diff

# Apply changes
chezmoi apply

# Update from remote repo and apply
chezmoi update
```

## Architecture

### chezmoi Source Layout

`.chezmoiroot` contains `home` — chezmoi treats `home/` as its source root. Repo metadata (README, install scripts, etc.) stays outside and is never deployed.

```text
home/
├── .chezmoiignore                          # Platform-specific filtering
├── dot_bashrc                              # → ~/.bashrc
├── dot_zshrc                               # → ~/.zshrc (sources ~/.bashrc)
├── git/
│   └── dot_stignore                       # → ~/git/.stignore (Syncthing ignore patterns)
├── dot_config/
│   ├── git/
│   │   ├── config.tmpl                    # → ~/.config/git/config (template: Windows sshCommand)
│   │   ├── config.home                    # → ~/.config/git/config.home
│   │   ├── config.work                    # → ~/.config/git/config.work
│   │   ├── config.codespaces              # → ~/.config/git/config.codespaces
│   │   └── ignore                         # → ~/.config/git/ignore
│   ├── fish/conf.d/
│   │   └── config.fish                    # → ~/.config/fish/conf.d/config.fish
│   ├── oh-my-posh/
│   │   └── jetersen.omp.json              # → ~/.config/oh-my-posh/jetersen.omp.json
│   ├── niri/
│   │   ├── config.kdl                    # → ~/.config/niri/config.kdl (main config, includes cfg/*.kdl)
│   │   ├── noctalia.kdl                  # → ~/.config/niri/noctalia.kdl (Noctalia theme colors)
│   │   └── cfg/                          # → ~/.config/niri/cfg/ (split config modules)
│   │       ├── animation.kdl
│   │       ├── autostart.kdl
│   │       ├── display.kdl
│   │       ├── input.kdl
│   │       ├── keybinds.kdl
│   │       ├── layout.kdl
│   │       ├── misc.kdl
│   │       └── rules.kdl
│   └── powershell/
│       └── Microsoft.PowerShell_profile.ps1  # → canonical pwsh profile
├── dot_githooks/
│   └── executable_commit-msg              # → ~/.githooks/commit-msg
├── private_dot_ssh/
│   └── config                             # → ~/.ssh/config (0700 dir perms)
├── Documents/
│   ├── PowerShell/
│   │   └── symlink_Microsoft.PowerShell_profile.ps1.tmpl  # Windows symlink
│   └── WindowsPowerShell/
│       └── symlink_Microsoft.PowerShell_profile.ps1.tmpl  # Windows symlink
```

### chezmoi Naming Conventions

- `dot_` prefix → leading `.` in target filename
- `executable_` prefix → file gets executable permission
- `private_` prefix → directory gets 0700 permissions
- `symlink_` prefix → file content is the symlink target path
- `modify_` prefix → source file is an executable script; chezmoi pipes the current target file to it on stdin and the script's stdout becomes the new target (see [Partially Managed Config](#partially-managed-config))
- `.tmpl` suffix → processed as a Go template by chezmoi
- Files without `.tmpl` are copied verbatim (safe for `{{ }}` in oh-my-posh JSON / PowerShell)

### Platform Filtering (`.chezmoiignore`)

- **Linux/macOS**: `Documents/` is ignored (no Windows PS symlinks needed)
- **Windows**: `.config/fish/`, `.bashrc`, and `.zshrc` are ignored (fish/bash/zsh not used on Windows)
- **Non-Hyprland**: `.config/hypr/` is ignored
- **Non-niri**: `.config/niri/`, `.config/DankMaterialShell/`, and `.local/bin/niri-focus-self` are ignored

### Git Config Hierarchy

`dot_config/git/config.tmpl` is the main config (XDG location: `~/.config/git/config`), which conditionally includes:

- `config.home` — when working in `~/git/code/` (personal, jetersen.dev email)
- `config.work` — when working in `~/git/work/` (work email)
- `config.codespaces` — when in `/workspaces/`

A `commit-msg` hook is deployed to `~/.githooks/` that prepends JIRA IDs from branch names.

### Partially Managed Config

Some apps own their own config file — they rewrite it whenever a setting changes and add or rename keys on every release. Version-controlling such a file wholesale makes `chezmoi diff` permanently noisy and lets `apply` revert the app's own schema migrations. For these, use a `modify_` script that pins only the keys worth sharing between machines and leaves the rest to the local app.

**`dot_config/DankMaterialShell/modify_settings.json.tmpl`** → `~/.config/DankMaterialShell/settings.json`

DankMaterialShell's `settings.json` has ~535 keys, but only ~27 differ from the values DMS ships. The script merges a 22-key overlay over whatever the machine currently has (plus one appended `appIdSubstitutions` rule, see caveats), using `jq`'s `*` operator so unlisted keys survive untouched. **The selection rule is "differs from the DMS default"** — pinning a key that already equals the default buys nothing and just creates upgrade churn. Machine-specific settings (wallpapers, display profiles, device pins, battery/AC timeouts) are left to the local app.

The defaults are readable from the installed package at `/usr/share/quickshell/dms/Common/settings/SettingsSpec.js`, so the overlay can be re-audited against a DMS upgrade — the script header carries a copy-pasteable snippet that lists every currently non-default key. Keys that differ from the default but are deliberately *not* pinned are listed there too, with reasons (schema-drift artefacts and the machine-specific `niriOutputSettings`).

Caveats:

- Arrays are replaced wholesale, not merged. `barConfigs` therefore overwrites each bar's `screenPreferences`; that is safe only while every machine uses `["all"]`.
- `appIdSubstitutions` is the exception: DMS ships its own rules in that array and extends them between releases, so it is handled outside the overlay and *appended* to whatever DMS currently ships (skipping patterns already present). On a fresh machine the key is left absent so DMS materialises its five defaults; the next `chezmoi apply` appends ours.
- Output deliberately omits a trailing newline to match how DMS writes the file, otherwise chezmoi reports a one-byte diff forever. This is the one place the repo's final-newline rule does not apply to the *generated* output — the script source itself still ends with a newline.
- Requires `jq` on PATH.
- `customThemeFile` pins a path into `dot_config/DankMaterialShell/themes/catppuccin/`, so that theme is version-controlled alongside it (see below). Without it, the five theme-related overlay keys would point at a missing file on a new machine.

**`dot_config/DankMaterialShell/themes/catppuccin/theme.json`** → `~/.config/DankMaterialShell/themes/catppuccin/theme.json`

Vendored, not app-managed. DMS registry themes are installed *manually* via Settings → Theme Browser, which copies them out of a throwaway clone at `/tmp/dankdots-plugin-registry/`; nothing re-fetches them automatically. So a new machine would otherwise show the stock purple theme until the theme was re-installed by hand, leaving `currentThemeName`, `currentThemeCategory`, `customThemeFile`, `registryThemeVariants` and `matugenScheme` pinned to a file that does not exist.

Unlike `settings.json`, DMS only writes this file at install time, so tracking it verbatim causes no diff churn. It is 15 KB of pure colour data — no absolute paths, hostnames, or secrets. The two `preview-*.svg` files next to it are theme-browser gallery art only and are deliberately left untracked.

### Syncthing Ignore Patterns

`git/dot_stignore` is deployed to `~/git/.stignore` and defines patterns for files/directories that Syncthing should not synchronize across devices. This prevents syncing:

- Build artifacts (bin, obj, node_modules, target, etc.)
- IDE metadata (.idea, .vs, .ionide)
- Secrets and credentials (.env, *.pem, *.key, credentials.json)
- Archives and compressed files (*.zip, *.tar.gz, *.json.gz)
- Large temporary outputs

### Shell Configs

**These three shell profiles must be kept in sync.** They share the same aliases, environment variables, functions, and PATH entries. When adding or changing a function/alias in one, apply the equivalent change to the other two.

- `dot_bashrc` — Bash/Zsh (Linux/macOS, used by Claude Code)
- `dot_config/fish/conf.d/config.fish` — Fish (primary interactive shell on Linux/macOS)
- `dot_config/powershell/Microsoft.PowerShell_profile.ps1` — PowerShell (Windows, cross-platform)

**Fish** (`dot_config/fish/conf.d/config.fish`): Primary interactive shell on Linux/macOS. Has custom `git clone`/`gh repo clone` wrappers that auto-cd into cloned directories, eza aliases, Oh My Posh prompt.

**Bash** (`dot_bashrc`): Bash equivalent of the Fish config, deployed to `~/.bashrc`. Provides the same aliases, functions, and environment so that tools running bash (e.g. Claude Code) have feature parity. `dot_zshrc` sources this file so zsh gets the same config.

**PowerShell** (`dot_config/powershell/Microsoft.PowerShell_profile.ps1`): Cross-platform profile with module management and Docker helpers. On Windows, `Documents/PowerShell/` and `Documents/WindowsPowerShell/` contain symlinks pointing to this canonical location.

### Deployment Paths

| Source | Destination |
| --- | --- |
| `dot_config/git/config.tmpl` | `~/.config/git/config` |
| `dot_config/git/config.home` | `~/.config/git/config.home` |
| `dot_config/git/config.work` | `~/.config/git/config.work` |
| `dot_config/git/config.codespaces` | `~/.config/git/config.codespaces` |
| `dot_config/git/gitignore` | `~/.config/git/gitignore` (global `core.excludesfile`) |
| `dot_githooks/executable_commit-msg` | `~/.githooks/commit-msg` |
| `private_dot_ssh/config` | `~/.ssh/config` |
| `git/dot_stignore` | `~/git/.stignore` |
| `dot_bashrc` | `~/.bashrc` |
| `dot_zshrc` | `~/.zshrc` |
| `dot_config/fish/conf.d/config.fish` | `~/.config/fish/conf.d/config.fish` |
| `dot_config/powershell/Microsoft.PowerShell_profile.ps1` | `~/.config/powershell/Microsoft.PowerShell_profile.ps1` |
| `dot_config/niri/config.kdl` | `~/.config/niri/config.kdl` |
| `dot_config/niri/noctalia.kdl` | `~/.config/niri/noctalia.kdl` |
| `dot_config/niri/cfg/*.kdl` | `~/.config/niri/cfg/*.kdl` |
| `dot_config/oh-my-posh/jetersen.omp.json` | `~/.config/oh-my-posh/jetersen.omp.json` |
| `dot_config/DankMaterialShell/modify_settings.json.tmpl` | `~/.config/DankMaterialShell/settings.json` (partial merge) |
| `dot_config/DankMaterialShell/themes/catppuccin/theme.json` | `~/.config/DankMaterialShell/themes/catppuccin/theme.json` |

## Code Style

- LF line endings, UTF-8 encoding everywhere (enforced by `.gitattributes`)
- 2-space indentation (tabs for gitconfig files)
- Trim trailing whitespace, insert final newline

Every text file **must** end with a final newline (enforced by `.editorconfig`). Some tools — notably Hyprland's and niri's config parsers — fail to process the last line of a file if it isn't followed by a newline. Always ensure new and edited files have one.
