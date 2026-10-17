"""Protect session trees and identify collisions using temporary home fixtures."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('home_audit', ROOT / 'scripts/rocket-home-audit.py')
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class HomeAuditTests(unittest.TestCase):
    def test_legacy_symlink_needs_review_without_reading_its_target(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            legacy = home / '.claude/CLAUDE.md'
            legacy.parent.mkdir()
            legacy.symlink_to('../.config/ai/AGENTS.md')
            managed = home / '.codex/AGENTS.md'
            managed.parent.mkdir()
            managed.symlink_to('/nix/store/example-home-manager-files/.codex/AGENTS.md')
            result = audit.audit(home, {
                'legacy': {'target': '.claude/CLAUDE.md'},
                'managed': {'target': '.codex/AGENTS.md'},
            })
            self.assertEqual(result['blockers'], [{
                'reason': 'Non-Home-Manager symlink requires handover review',
                'path': '.claude/CLAUDE.md',
            }])
            self.assertTrue(legacy.is_symlink())

    def test_preserved_sessions_and_volatile_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            history = home / '.codex/sessions/session.jsonl'
            history.parent.mkdir(parents=True)
            history.write_text('user-generated session')
            profile = home / '.mozilla/firefox/profile'
            profile.parent.mkdir(parents=True)
            profile.symlink_to('/run/user/1000/psd/profile')
            result = audit.audit(home, {'bad': {'target': '.codex/sessions'}})
            self.assertEqual(len(result['blockers']), 2)
            self.assertEqual(history.read_text(), 'user-generated session')
            self.assertEqual(result['preserve']['.codex/sessions']['kind'], 'directory')

    def test_collision_backup_and_no_following_skill_links(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            (home / '.bashrc').write_text('old shell')
            (home / '.bashrc.pre-nixos').write_text('previous backup')
            result = audit.audit(home, {'shell': {'target': '.bashrc'}})
            self.assertTrue(result['collisions'][0]['backup_exists'])
            self.assertEqual(len(result['blockers']), 1)
            with self.assertRaises(ValueError):
                audit.audit(home, {'escape': {'target': '../outside'}})
            with self.assertRaises(ValueError):
                audit.audit(home, {'escape': {'target': '/etc/passwd'}})


if __name__ == '__main__':
    unittest.main()
