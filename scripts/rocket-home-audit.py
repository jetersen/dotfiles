#!/usr/bin/env python3
"""Read metadata only; report the handover boundaries without changing home files."""
import argparse
from fnmatch import fnmatchcase
import json
import os
from pathlib import Path

# These trees contain sessions, worktrees, identities or application-managed settings.
# Individual instructions/skills beneath Codex/Claude are intentionally HM-managed.
PRESERVE = (
    '.t3', '.t3-desktop', '.config/t3code', '.config/t3code-v2', '.config/Codex',
    '.codex/sessions', '.codex/archived_sessions', '.codex/worktrees', '.codex/attachments',
    '.codex/memories', '.codex/auth.json', '.claude/projects', '.claude/sessions',
    '.claude/file-history', '.claude/.credentials.json', '.local/state/local-git-sync',
    '.local/share/kwalletd', '.local/share/keyrings', '.zen', '.mozilla',
)
RETIRE = (
    '.config/fish/conf.d/config.fish',
    '.config/powershell/Microsoft.PowerShell_profile.ps1',
    '.config/systemd/user/t3code.service',
    '.config/systemd/user/default.target.wants/t3code.service',
    '.config/systemd/user/claude-code-proxy.service',
    '.config/systemd/user/default.target.wants/claude-code-proxy.service',
    '.config/systemd/user/default.target.wants/psd.service',
    '.local/bin/claude', '.local/bin/codex', '.local/bin/topf',
    '.local/bin/music-assistant-companion', '.local/bin/youtube-music',
    '.local/bin/argocd-worklaptop-sso', '.local/bin/worklaptop-clip',
    '.local/share/applications/t3code.desktop',
    '.local/share/applications/t3code-url-handler.desktop',
    '.local/share/applications/com.t3tools.T3Code.desktop',
)


def metadata(path):
    if not os.path.lexists(path):
        return {'kind': 'absent'}
    stat = path.lstat()
    item = {'kind': 'symlink' if path.is_symlink() else 'directory' if path.is_dir() else 'file',
            'mode': oct(stat.st_mode & 0o777), 'uid': stat.st_uid, 'gid': stat.st_gid}
    if path.is_symlink():
        item['link'] = os.readlink(path)
        item['dangling'] = not path.exists()
    return item


def audit(home, managed):
    collisions, blockers = [], []
    for item in managed.values():
        relative = Path(item['target'])
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError('Managed target escapes home')
        name = relative.as_posix()
        for protected in PRESERVE:
            if name == protected or name.startswith(protected + '/') or protected.startswith(name + '/'):
                blockers.append({'reason': 'Home Manager overlaps preserved state', 'path': name})
        current = metadata(home / relative)
        if current['kind'] != 'absent':
            backup = os.path.lexists(str(home / relative) + '.pre-nixos')
            collisions.append({'path': name, **current, 'backup_exists': backup,
                               'force': item.get('force', False)})
            if backup or item.get('force', False):
                blockers.append({'reason': 'Existing backup or forced replacement needs review', 'path': name})
            if current['kind'] == 'symlink' and not fnmatchcase(
                    current['link'], '/nix/store/*-home-manager-files/*'):
                blockers.append({'reason': 'Non-Home-Manager symlink requires handover review', 'path': name})
    profiles = []
    for pattern in ('.mozilla/firefox/*', '.zen/*', '.config/BraveSoftware/*'):
        for path in home.glob(pattern):
            if path.is_symlink() and os.readlink(path).startswith(('/run/', '/tmp/')):
                profiles.append(str(path.relative_to(home)))
    blockers.extend({'reason': 'Browser profile still points to volatile storage', 'path': p} for p in profiles)
    return {
        'managed_count': len(managed), 'collisions': collisions, 'blockers': blockers,
        'preserve': {p: metadata(home / p) for p in PRESERVE},
        'retire_after_backup': {p: metadata(home / p) for p in RETIRE if os.path.lexists(home / p)},
        'mutable_config_backup': ['.codex/config.toml', '.claude.json', '.claude/settings.json',
                                  '.config/DankMaterialShell/settings.json',
                                  '.config/music-assistant-companion/settings.json',
                                  '.config/YouTube Music/config.json'],
        'note': 'Metadata only. Package/database version compatibility and a clean shutdown require separate verification.',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, default=Path.home())
    parser.add_argument('--managed-files', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = audit(args.home, json.loads(args.managed_files.read_text()))
    # Reports contain private filesystem paths. Never overwrite an existing file.
    descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump(result, stream, indent=2)
        stream.write('\n')
    print(f"Audited {result['managed_count']} managed paths; "
          f"{len(result['collisions'])} existing paths; {len(result['blockers'])} blockers.")


if __name__ == '__main__':
    main()
