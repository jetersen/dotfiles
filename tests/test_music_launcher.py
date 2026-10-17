"""Exercise music focus, tray restore and launch without touching real applications."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'home/dot_local/bin/executable_focus-music-assistant'
MOCK = '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
root = Path(os.environ['FIXTURE'])
with (root / 'calls').open('a') as stream:
    stream.write(json.dumps([name, *sys.argv[1:]]) + '\\n')
mode = os.environ['MODE']
if name == 'niri':
    if sys.argv[1:] == ['msg', '-j', 'windows']:
        if mode == 'unavailable':
            sys.exit(1)
        visible = mode == 'visible' or (root / 'restored').exists()
        print(json.dumps([{'id': 42, 'app_id': 'music-assistant-companion'}] if visible else []))
elif name == 'busctl':
    if 'list' in sys.argv and mode == 'hidden':
        print('org.mpris.MediaPlayer2.io_music_assistant_companion.instance123 123 companion')
    elif 'Raise' in sys.argv:
        (root / 'restored').touch()
'''


class MusicLauncherTests(unittest.TestCase):
    def run_launcher(self, mode, *args):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for command in ('niri', 'busctl', 'music-assistant-companion'):
                path = root / command
                path.write_text(MOCK)
                path.chmod(0o755)
            env = dict(os.environ, FIXTURE=directory, MODE=mode,
                       PATH=directory + os.pathsep + os.environ['PATH'])
            subprocess.run(['bash', str(SCRIPT), *args], env=env, check=True, timeout=5)
            return [json.loads(line) for line in (root / 'calls').read_text().splitlines()]

    def test_existing_window_is_focused_without_launching_another_client(self):
        calls = self.run_launcher('visible')
        self.assertIn(['niri', 'msg', 'action', 'focus-window', '--id', '42'], calls)
        self.assertFalse(any(call[0] == 'music-assistant-companion' for call in calls))

    def test_hidden_window_is_restored_and_focused_without_another_client(self):
        calls = self.run_launcher('hidden')
        self.assertTrue(any(call[0] == 'busctl' and 'Raise' in call for call in calls))
        self.assertIn(['niri', 'msg', 'action', 'focus-window', '--id', '42'], calls)
        self.assertFalse(any(call[0] == 'music-assistant-companion' for call in calls))

    def test_stopped_client_is_launched_with_arguments(self):
        calls = self.run_launcher('stopped', 'argument with spaces')
        self.assertEqual(calls[-1], ['music-assistant-companion', 'argument with spaces'])

    def test_launches_without_a_running_niri_session(self):
        calls = self.run_launcher('unavailable')
        self.assertEqual(calls[-1], ['music-assistant-companion'])


if __name__ == '__main__':
    unittest.main()
