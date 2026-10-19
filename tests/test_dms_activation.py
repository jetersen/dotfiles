"""Run with the built configure-dms executable as the first argument."""
import os
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

CONFIGURE_DMS = sys.argv.pop(1) if __name__ == '__main__' and len(sys.argv) > 1 else None


@unittest.skipUnless(CONFIGURE_DMS, 'requires the built configure-dms executable')
class DmsActivationTests(unittest.TestCase):
  def activate(self, root):
    environment = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_DATA_HOME=str(root / 'data'), XDG_DATA_DIRS='/no-system-data',
                       PATH='/no-ambient-tools')
    result = subprocess.run([CONFIGURE_DMS], env=environment, capture_output=True)
    self.assertEqual(result.returncode, 0, result.stderr.decode())
    self.assertNotIn(b"command not found", result.stderr)

  def test_fresh_activation_and_repeat_work_without_ambient_niri(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      self.activate(root)
      binds = root / 'config/niri/dms/binds.kdl'
      settings = json.loads((root / 'config/DankMaterialShell/settings.json').read_text())
      self.assertGreater(len(settings['appIdSubstitutions']), 1)
      before = binds.read_bytes()
      self.assertNotIn(b'Alt+Space', before)
      self.assertIn(b'binds {', before)
      self.activate(root)
      self.assertEqual(binds.read_bytes(), before)

  def test_existing_custom_bind_survives_removal(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      binds = root / 'config/niri/dms/binds.kdl'
      binds.parent.mkdir(parents=True)
      binds.write_text('binds {\n Alt+Space { spawn "dms" "ipc" "spotlight" "toggle"; }\n Mod+F11 { spawn "keep-me"; }\n}\n')
      self.activate(root)
      before = binds.read_bytes()
      self.assertNotIn(b'Alt+Space', before)
      self.assertIn(b'keep-me', before)
      self.activate(root)
      self.assertEqual(binds.read_bytes(), before)

  def test_settings_preserve_local_values_and_extra_bars(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      settings = root / 'config/DankMaterialShell/settings.json'
      settings.parent.mkdir(parents=True)
      custom = {'pattern': 'my-app', 'replacement': 'my-icon', 'type': 'exact'}
      extra = {'id': 'side', 'screenPreferences': ['DP-9'], 'custom': 42}
      settings.write_text(json.dumps({
        'localSetting': {'keep': True}, 'animationSpeed': 999,
        'barConfigs': [{'id': 'default', 'screenPreferences': ['DP-1'], 'local': 17}, extra],
        'appIdSubstitutions': [custom],
      }))
      self.activate(root)
      data = json.loads(settings.read_text())
      self.assertEqual(data['localSetting'], {'keep': True})
      self.assertEqual(data['animationSpeed'], 0)
      self.assertEqual(data['barConfigs'][0]['screenPreferences'], ['DP-1'])
      self.assertEqual(data['barConfigs'][0]['local'], 17)
      self.assertEqual(data['barConfigs'][1], extra)
      self.assertIn(custom, data['appIdSubstitutions'])
      self.assertEqual(sum(x['pattern'] == 'com.github.th_ch.youtube_music'
                           for x in data['appIdSubstitutions']), 1)
      before = settings.read_bytes()
      self.activate(root)
      self.assertEqual(settings.read_bytes(), before)

  def test_real_gtk_script_with_generated_colors(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      self.activate(root)
      self.assertFalse((root / 'data/themes').exists())
      css = '/* BEGIN DMS OVERRIDE */\n@define-color test_color #123456;\n/* END DMS OVERRIDE */\n'
      for version in ['3', '4']:
        folder = root / f'config/gtk-{version}.0'
        folder.mkdir(parents=True)
        (folder / 'dank-colors.css').write_text(css)
        (folder / 'gtk.css').write_text('/* local stylesheet */\n')
      self.activate(root)
      gtk4 = root / 'config/gtk-4.0/gtk.css'
      self.assertIn('local stylesheet', gtk4.read_text())
      self.assertEqual(gtk4.read_text().count('@import'), 1)
      theme = root / 'data/themes/adw-gtk3-dark/gtk-3.0/gtk.css'
      self.assertIn(css, theme.read_text())
      before = theme.read_bytes()
      self.activate(root)
      self.assertEqual(theme.read_bytes(), before)
      self.assertEqual(gtk4.read_text().count('@import'), 1)


if __name__ == '__main__':
  unittest.main()
