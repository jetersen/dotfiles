import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
  'clipboard', Path(__file__).resolve().parents[1] / 'nixos/home/wayland-clipboard.py')
clipboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clipboard)


class DesktopEnvironmentTests(unittest.TestCase):
  @patch.object(clipboard.subprocess, 'check_output')
  def test_remote_session_recovers_desktop_without_replacing_path(self, output):
    output.return_value = b'{"WAYLAND_DISPLAY":"wayland-1","PATH":"desktop-path"}'
    with patch.object(clipboard.os, 'getuid', return_value=1000):
      env = clipboard.desktop_environment({'PATH': 'ssh-path'})
    self.assertEqual(env, {'PATH': 'ssh-path', 'XDG_RUNTIME_DIR': '/run/user/1000',
                           'WAYLAND_DISPLAY': 'wayland-1'})
    self.assertEqual(output.call_args.kwargs['env']['XDG_RUNTIME_DIR'], '/run/user/1000')

  @patch.object(clipboard.subprocess, 'check_output')
  def test_existing_desktop_is_untouched(self, output):
    original = {'WAYLAND_DISPLAY': 'custom', 'XDG_RUNTIME_DIR': '/custom'}
    self.assertEqual(clipboard.desktop_environment(original), original)
    output.assert_not_called()

  @patch.object(clipboard.subprocess, 'check_output')
  def test_partial_environment_preserves_display(self, output):
    output.return_value = b'{"WAYLAND_DISPLAY":"wayland-1"}'
    self.assertEqual(clipboard.desktop_environment({'WAYLAND_DISPLAY': 'custom'})[
      'WAYLAND_DISPLAY'], 'custom')

  @patch.object(clipboard.subprocess, 'check_output')
  def test_no_desktop_leaves_diagnostics_to_wl_clipboard(self, output):
    output.side_effect = subprocess.TimeoutExpired('systemctl', 5)
    self.assertNotIn('WAYLAND_DISPLAY', clipboard.desktop_environment({}))


if __name__ == '__main__':
  unittest.main()
