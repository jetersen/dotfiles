"""Run with the built configure-dms executable as the first argument."""
import os
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
                       PATH='/no-ambient-tools')
    subprocess.run([CONFIGURE_DMS], env=environment, check=True, capture_output=True)

  def test_fresh_activation_and_repeat_work_without_ambient_niri(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      self.activate(root)
      binds = root / 'config/niri/dms/binds.kdl'
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


if __name__ == '__main__':
  unittest.main()
