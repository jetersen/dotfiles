# Dotfiles

The root Nix flake manages NixOS through `nixos/`, Disko, sops-nix, and Home Manager.
Installation instructions are in `README.md`.

## Working here

- Work on `main` unless asked to create a branch or worktree.
- Use Conventional Commits, for example `feat(nixos): add workstation tools`.
- Forgejo is primary; its native push mirror updates GitHub. Push to `origin` on
  Forgejo. All NixOS hosts deploy from `main`; CI caches the system before notifying
  each host. Do not introduce per-host deployment branches.
- Keep `main` linear; do not create merge commits. Both hosts follow
  the current `main` revision, including authorized rewritten history.
- Preserve Renovate's author and committer as `renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>`.
  Use Forgejo's `fast-forward-only` merge style and let Renovate rebase outdated
  branches. Keep `automergeStrategy: "auto"`; Renovate 44.132.2 uses strict fast-forward
  for `"fast-forward"` when allowed, with a rebase fallback. Keep the strict repository default.
- Prefer the normal CI/Attic/systemd deployment path: push authorized changes to
  `origin/main`, wait for CI to cache the target revision, then let the on-demand NixOS upgrade service deploy.
  If a manual check is needed, start `nixos-upgrade.service` on the target host.
  Use local `nixos-rebuild` only as a fallback when that path is unavailable or
  for explicitly requested local testing or recovery. Explain why before using it.
- Edit NixOS and Home Manager configuration under `nixos/`. Shared plain assets
  live under `nixos/assets/`.
- Keep NixOS hardware and disk identities host-specific, and verify the disk's
  persistent ID before installing with Disko. Generate hardware configuration on
  the target. Do not bump NixOS or Home Manager state versions for package updates.
- Keep plaintext secrets and private keys out of Nix expressions and the Nix store.
  Use sops-nix for deployed secrets.
## Conventions that matter

- Shared aliases and environment variables belong in `nixos/home/shell.nix`.
  Shell-specific functions live in `nixos/home/shell/`.
- DMS settings are managed by `nixos/home/dms.nix` and
  `nixos/home/dms-activation.nix`. Preserve machine-specific settings and extra bars.
- DMS theme data is tracked because DMS does not reinstall it automatically.
- Follow `.editorconfig`. The DMS modifier's generated JSON intentionally has no trailing newline; its source file still needs one.

## Validation

Run `git diff --check` and checks appropriate to the changed file. For modifier scripts,
verify fresh input, preservation of existing local settings, and idempotence. Review the target diff before applying; report which machines
were actually updated.
