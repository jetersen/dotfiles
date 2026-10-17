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

  def test_vite_handover_also_runs_after_original_migration(self):
    with tempfile.TemporaryDirectory() as directory:
      home = Path(directory)
      marker = home / '.local/state/dotfiles/nixos-startup-migrated'
      marker.parent.mkdir(parents=True)
      marker.touch()
      fish = home / '.config/fish/conf.d'
      fish.mkdir(parents=True)
      (fish / 'config.fish').write_text('new intentional startup\n')
      legacy = fish / 'vite-plus.fish'
      legacy.write_text('source old-vite-env\n')
      command = ['bash', str(SCRIPT), directory]
      subprocess.run(command, check=True)
      self.assertFalse(legacy.exists())
      self.assertEqual(Path(str(legacy) + '.pre-nixos').read_text(), 'source old-vite-env\n')
      self.assertEqual((fish / 'config.fish').read_text(), 'new intentional startup\n')
      legacy.write_text('new intentional vite startup\n')
      subprocess.run(command, check=True)
      self.assertEqual(legacy.read_text(), 'new intentional vite startup\n')

  def test_vite_backup_conflict_preserves_all_startup_files(self):
    with tempfile.TemporaryDirectory() as directory:
      home = Path(directory)
      fish = home / '.config/fish/conf.d'
      fish.mkdir(parents=True)
      (fish / 'config.fish').write_text('original')
      (fish / 'vite-plus.fish').write_text('original vite')
      (fish / 'vite-plus.fish.pre-nixos').write_text('existing backup')
      result = subprocess.run(['bash', str(SCRIPT), directory], capture_output=True)
      self.assertNotEqual(result.returncode, 0)
      self.assertEqual((fish / 'config.fish').read_text(), 'original')
      self.assertEqual((fish / 'vite-plus.fish').read_text(), 'original vite')
      self.assertFalse((home / '.local/state/dotfiles/nixos-startup-migrated').exists())


if __name__ == '__main__':
  unittest.main()
