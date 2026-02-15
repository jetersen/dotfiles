# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Cross-platform dotfiles repository managing configurations for Fish, PowerShell, Git, SSH, and Oh My Posh. Targets Linux (CachyOS), macOS, Windows, and GitHub Codespaces. Managed with [chezmoi](https://www.chezmoi.io/).

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
- `.tmpl` suffix → processed as a Go template by chezmoi
- Files without `.tmpl` are copied verbatim (safe for `{{ }}` in oh-my-posh JSON / PowerShell)

### Platform Filtering (`.chezmoiignore`)

- **Linux/macOS**: `Documents/` is ignored (no Windows PS symlinks needed)
- **Windows**: `.config/fish/`, `.bashrc`, and `.zshrc` are ignored (fish/bash/zsh not used on Windows)

### Git Config Hierarchy

`dot_config/git/config.tmpl` is the main config (XDG location: `~/.config/git/config`), which conditionally includes:

- `config.home` — when working in `~/git/code/` (personal, jetersen.dev email)
- `config.work` — when working in `~/git/work/` (work email)
- `config.codespaces` — when in `/workspaces/`

A `commit-msg` hook is deployed to `~/.githooks/` that prepends JIRA IDs from branch names.

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
| `dot_config/git/ignore` | `~/.config/git/ignore` |
| `dot_githooks/executable_commit-msg` | `~/.githooks/commit-msg` |
| `private_dot_ssh/config` | `~/.ssh/config` |
| `git/dot_stignore` | `~/git/.stignore` |
| `dot_bashrc` | `~/.bashrc` |
| `dot_zshrc` | `~/.zshrc` |
| `dot_config/fish/conf.d/config.fish` | `~/.config/fish/conf.d/config.fish` |
| `dot_config/powershell/Microsoft.PowerShell_profile.ps1` | `~/.config/powershell/Microsoft.PowerShell_profile.ps1` |
| `dot_config/oh-my-posh/jetersen.omp.json` | `~/.config/oh-my-posh/jetersen.omp.json` |

## Code Style

- LF line endings, UTF-8 encoding everywhere (enforced by `.gitattributes`)
- 2-space indentation (tabs for gitconfig files)
- Trim trailing whitespace, insert final newline

Every text file **must** end with a final newline (enforced by `.editorconfig`). Some tools — notably Hyprland's config parser — fail to process the last line of a file if it isn't followed by a newline. Always ensure new and edited files have one.
