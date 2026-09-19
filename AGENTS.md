# Dotfiles

Chezmoi manages these dotfiles across CachyOS, macOS, Windows, and Codespaces.
`home/` is the source root (see `.chezmoiroot`); repository metadata is not deployed.
Installation instructions are in `README.md`.

## Working here

- Work on `main` unless asked to create a branch or worktree.
- Edit chezmoi source files under `home/`. If applying a change locally, keep the source and deployed file consistent.
- `.tmpl` files use Go templates; check relevant OS and `isWork` variants. `modify_` scripts transform an existing file supplied on stdin, so preserve unmanaged settings.
- Inspect the source-state hook in `home/.chezmoi.toml.tmpl` before invoking chezmoi. Even read commands can trigger Proton Pass login. Avoid a whole-repository apply for a focused change; deployment scripts can install packages and change system settings.

## Conventions that matter

- Shared aliases, environment variables, and functions must stay consistent across `home/dot_bashrc`, `home/dot_config/fish/conf.d/config.fish`, and `home/dot_config/powershell/Microsoft.PowerShell_profile.ps1`. Zsh sources the Bash configuration.
- DMS settings are partially managed by `home/dot_config/DankMaterialShell/modify_settings.json.tmpl`. Pin intentional differences from upstream defaults, preserve machine-specific settings and extra bars, and read the script comments before changing merge behavior.
- DMS theme data under `home/dot_config/DankMaterialShell/themes/` is tracked because DMS does not reinstall it automatically.
- Follow `.editorconfig`. The DMS modifier's generated JSON intentionally has no trailing newline; its source file still needs one.

## Validation

Run `git diff --check` and checks appropriate to the changed file. For modifier scripts,
render relevant template variants and verify fresh input, preservation of existing local
settings, and idempotence. Review the target diff before applying; report which machines
were actually updated.
