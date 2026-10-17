"""Verify Rocket's one-time startup-file migration only moves reviewed legacy files."""

from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'nixos/hosts/rocket/retire-chezmoi-startup.sh'


class StartupMigrationTests(unittest.TestCase):
  def test_preserves_files_and_runs_only_once(self):
    with tempfile.TemporaryDirectory() as directory:
      home = Path(directory)
      legacy = home / '.config/fish/conf.d/config.fish'
      legacy.parent.mkdir(parents=True)
      legacy.write_text('old startup\n')
      command = ['bash', str(SCRIPT), directory]
      subprocess.run(command, check=True)
      self.assertFalse(legacy.exists())
      self.assertEqual(Path(str(legacy) + '.pre-nixos').read_text(), 'old startup\n')
      legacy.write_text('new intentional startup\n')
      subprocess.run(command, check=True)
      self.assertEqual(legacy.read_text(), 'new intentional startup\n')

  def test_existing_backup_aborts_before_any_move(self):
    with tempfile.TemporaryDirectory() as directory:
      home = Path(directory)
      paths = [home / '.config/fish/conf.d/config.fish',
               home / '.config/powershell/Microsoft.PowerShell_profile.ps1']
      for path in paths:
        path.parent.mkdir(parents=True)
        path.write_text('keep')
      Path(str(paths[1]) + '.pre-nixos').write_text('existing backup')
      result = subprocess.run(['bash', str(SCRIPT), directory], capture_output=True)
      self.assertNotEqual(result.returncode, 0)
      self.assertTrue(all(path.read_text() == 'keep' for path in paths))
      self.assertFalse((home / '.local/state/dotfiles/nixos-startup-migrated').exists())


if __name__ == '__main__':
  unittest.main()
