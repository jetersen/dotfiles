# Rocket home handover

Reuse `@home` and UID/GID 1000. Preserve the full home archive before the first
NixOS activation. Do not initialize a fresh home, run chezmoi on NixOS, or replace
whole application directories with declarative configuration. Configuration
handover is limited to the paths Home Manager owns and reviewed legacy launchers.

## State to preserve

| State | Preserve |
| --- | --- |
| T3 Code | Entire `~/.t3`, `~/.t3-desktop`, `~/.config/t3code`, and `~/.config/t3code-v2` |
| Codex | Entire `~/.codex` and desktop profile `~/.config/Codex`; only the declared `AGENTS.md` is replaced |
| Claude | Entire `~/.claude` and `~/.claude.json`; only declared instructions and individual pinned skills are replaced |
| Projects | `~/git`, T3/Codex worktrees, project metadata, untracked files, and `~/.local/state/local-git-sync` |
| Credentials | SSH/GPG material, `~/.local/share/kwalletd`, `~/.local/share/keyrings` if present, and application authentication files |
| Other applications | Browser profiles, editor state, game saves, Wine prefixes, DMS local state, music player identities and login caches |

Keep the same absolute project paths. `~/git` can point into local-git-sync
state, and worktrees can refer to Git metadata elsewhere in home; moving only
visible checkouts or recreating their symlinks loses that relationship.

T3's database is not its complete state: preserve attachments, secrets, settings,
worktrees, browser profiles, saved environments, and runtime metadata together.
Electron profiles and the original wallet matter for encrypted credentials.
NixOS's GNOME Keyring does not automatically import or unlock a KWallet wallet;
retain the original wallet and password and expect that some applications may
need reauthentication. Never reset the old wallet to make a login dialog go away.

Codex's [configuration documentation](https://learn.chatgpt.com/docs/config-file/config-advanced)
describes `CODEX_HOME`; preserve an explicitly configured location as well as
any custom SQLite location. Claude stores resumable transcripts per project;
see its [session documentation](https://code.claude.com/docs/en/sessions).
Preserve custom settings, hooks, agents, plugins, memories, and rules. Check
retention settings before opening a new client version, since application
startup can perform cleanup as well as schema migration.

## Audit the intended configuration

Run from the dotfiles checkout without applying anything:

```sh
nix --extra-experimental-features 'nix-command flakes' eval --impure --json --expr '
  let
    f = builtins.getFlake (toString ./.);
    h = f.nixosConfigurations.rocket.config.home-manager.users.joseph;
  in builtins.mapAttrs (_: v: {
    inherit (v) target force recursive;
    source = toString v.source;
  }) (f.inputs.nixpkgs.lib.filterAttrs (_: v: v.enable) h.home.file)
' > /tmp/rocket-home-managed.json
python3 scripts/rocket-home-audit.py \
  --managed-files /tmp/rocket-home-managed.json \
  --output /tmp/rocket-home-audit.json
```

The audit reads metadata, not conversations or credential contents. It reports
existing targets, backup collisions, volatile browser links, and legacy paths
for review. Reports are private and are not committed. Rerun after configuration
changes; use a new output filename rather than overwriting the previous report.
The audit does not prove database compatibility or replace the offline backup.

Home Manager backs up conflicting paths with `.pre-nixos`; it must not force
replacement or overwrite an earlier backup. Review whole-directory targets such
as pinned skills, PowerShell modules, GitHub CLI extensions, and Wallpapers.
Keep extra user-created content from their backups or move it to an unmanaged
location before adoption. Do not restore the entire old directory over a Nix link.
Existing symlinks outside a Home Manager generation need separate review: Home
Manager's automatic backup does not move them. After verifying the offline backup,
move conflicting legacy links aside before activation. Keep retired autostart
links in the private handover directory, outside systemd's `*.wants` directories.

Some files are updated in place after linking, so they are not ordinary symlink
collisions: Codex `config.toml`, `.claude.json`, GitHub CLI settings, DMS settings,
Pear Desktop settings, and Music Assistant settings. The offline home archive
preserves their original contents. The AI reconciler changes its managed MCP
entries while retaining other configuration. Existing custom hooks, providers,
and MCP commands still need their executable paths checked on NixOS.

## Before leaving CachyOS

1. Finish AI turns, delegated work, scheduled jobs, and CI jobs. Close the T3
   desktop and Codex/Claude clients. T3's background service can outlive its window;
   stop `t3code.service` explicitly after closing the desktop. Also stop the
   custom `claude-code-proxy.service` after its clients exit. Record their enabled
   state in the private migration report before stopping them.
2. Close browsers, then stop `psd.service` through systemd so profile-sync-daemon
   restores RAM-backed browser profiles. Verify no profile directory under
   `.mozilla/firefox`, `.zen`, or `.config/BraveSoftware` points into `/run` or
   `/tmp`. Do not delete such a link: fix the sync/restore while CachyOS still runs.
3. Stop other writers, including Syncthing and local-git-sync, when ready for the
   actual transition. Preserve their state; do not reset enrollment or indexes.
4. Enter the RAM-based NixOS installer with kexec, or boot external live media.
   Mount the old filesystems read-only, then run and verify the encrypted backup
   as described in [the installation procedure](rocket-install.md).

Back up entire database directories, including any `-wal`, `-shm`, or journal
files. Do not delete these files to tidy the backup. SQLite explains why WAL is
part of persistent database state in its [WAL documentation](https://www.sqlite.org/wal.html).
Test integrity on private extracted copies, not the only original databases.
Do not open an uncheckpointed WAL database using SQLite's `immutable=1` option,
which can ignore its WAL. An ordinary writable staging copy can recover it.

## Offline handover and first login

After verifying the backup and before allowing the first NixOS user session:

- Move only reviewed legacy files aside with `.pre-nixos` names; preflight every
  destination and stop if any already exists. The audit's retirement list is a
  proposal, not an automatic deletion list. The existing Home Manager activation
  handles the legacy shell startup files once. It also retires Vite+'s Fish
  startup hook so downloaded runtimes do not shadow the Nix-provided commands.
- Retire the old T3 and Claude proxy unit files and their autostart symlinks.
  Keep their runtime, configuration, and data directories. Recreate the services
  declaratively only after compatible packages and commands are ready. Do not
  start the old home-installed T3 runtime automatically on NixOS.
- Retire profile-sync-daemon's old activation link after its successful unsync.
  NixOS initially uses the browser profiles on disk.
- Move reviewed user-installed launchers aside when Nix supplies that command.
  In particular, check `claude`, `codex`, `topf`, and music helpers in `.local/bin`.
  This directory is still on PATH and must remain available for custom scripts.
  Keep downloaded package directories for recovery until migration is accepted.
- Review user desktop entries that shadow Nix launchers, especially T3's desktop
  and URL handlers. Keep user-created entries that still work. Do not delete the
  entire applications directory or all user services.

Rocket declares T3 as a user service with lingering enabled. T3's server uses
`~/.t3`; its desktop and historical URL handlers use `~/.t3-desktop`.
Keep the desktop's local server setting disabled when using the background
server. Nix manages the T3 executable and updates. Syncthing remains disabled;
its preserved state is available for recovery.

Before opening real AI data, compare installed versions with the last CachyOS
versions. Do not launch an older T3/Codex client against newer databases. Align
the Nix package first and test an isolated, private copy of its full data tree.
An isolated T3 test must isolate `T3CODE_HOME`, Electron's profile, and background
services together; changing only one path is insufficient. Do not connect a test
copy to live automation or allow it to run queued jobs. Resolve local proxy and
system-specific MCP paths before expecting existing provider configuration to work.

On first login, verify `type -a claude codex t3code t3code-desktop` and desktop
launchers select the intended Nix packages. Check that session lists, attachments,
project paths, worktrees, custom skills, and authentication are intact. Resume a
known session only after that inspection. Verify browser profiles and editor
history too. Keep Comin disabled and retain the home backup until these checks
pass; an OS-generation rollback cannot undo application database migrations.
