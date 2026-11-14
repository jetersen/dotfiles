"""Check layout synchronization and picker exclusion without reading or injecting keys."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('layout', ROOT / 'nixos/home/espanso-layout.py')
layout = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layout)
generator_spec = importlib.util.spec_from_file_location(
    'shortcodes', ROOT / 'nixos/packages/generate-emoji-shortcodes.py')
generator = importlib.util.module_from_spec(generator_spec)
generator_spec.loader.exec_module(generator)


class EmojiExpansionTests(unittest.TestCase):
    def test_custom_sequences_and_alias_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            generator.generate([{'emoji': '👏', 'aliases': ['clap']}],
                               {'ship_it': '🚢🚀', 'clap': '👏🎉'}, root)
            matches = json.loads((root / 'emoji.yml').read_text())['matches']
            self.assertEqual({item['trigger']: item['replace'] for item in matches},
                             {':clap:': '👏🎉', ':ship_it:': '🚢🚀'})
            self.assertEqual(len(matches), 2, 'custom overrides must not create duplicate triggers')
            self.assertNotIn('shipit', json.loads((root / 'shortcodes.json').read_text()))

    def test_layout_snapshot_switch_and_unrelated_events(self):
        codes = layout.layout_codes((ROOT / 'home/dot_config/niri/cfg/input.kdl').read_text())
        self.assertEqual(codes, ['us', 'dk'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'config').mkdir()
            ready = []
            layout.watch(root, codes, io.StringIO(json.dumps({
                'KeyboardLayoutsChanged': {'keyboard_layouts': {
                    'names': ['English (US)', 'Danish'], 'current_idx': 1}}}) + '\n'),
                lambda: ready.append(True))
            target = root / 'config/default.yml'
            self.assertEqual(json.loads(target.read_text())['keyboard_layout'], {'layout': 'dk'})
            self.assertEqual(ready, [True])
            before = target.stat().st_mtime_ns
            layout.watch(root, codes, io.StringIO('{"OtherEvent": {}}\n'), lambda: None)
            self.assertEqual(target.stat().st_mtime_ns, before)
            layout.watch(root, codes, io.StringIO('{"KeyboardLayoutSwitched": {"idx": 0}}\n'), lambda: None)
            settings = json.loads(target.read_text())
            self.assertEqual(settings['keyboard_layout'], {'layout': 'us'})
            self.assertEqual(settings['search_shortcut'], 'off')

    def run_control(self, directory, action):
        return subprocess.run(['bash', '-euo', 'pipefail',
                               str(ROOT / 'nixos/home/emoji-expansion-control.sh'), action],
                              env=dict(os.environ, XDG_RUNTIME_DIR=directory,
                                       PATH=directory + os.pathsep + os.environ['PATH']),
                              check=True)

    def test_picker_stops_and_restores_only_a_running_service(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / 'systemctl'
            fake.write_text(f'#!{shutil.which("bash")}\n' + '''set -eu
cd "$XDG_RUNTIME_DIR"
case "$2" in
 is-active) test -f active ;;
 stop) echo stop >> calls; rm active ;;
 start) echo start >> calls; touch active ;;
 *) exit 2 ;;
esac
''')
            fake.chmod(0o700)
            self.run_control(directory, 'pause')
            self.run_control(directory, 'resume')
            self.assertFalse((root / 'calls').exists(), 'do not enable a previously stopped service')
            (root / 'active').touch()
            self.run_control(directory, 'pause')
            self.run_control(directory, 'pause')
            self.assertFalse((root / 'active').exists())
            self.run_control(directory, 'resume')
            self.run_control(directory, 'resume')
            self.assertTrue((root / 'active').exists())
            self.assertEqual((root / 'calls').read_text().splitlines(), ['stop', 'start'])


if __name__ == '__main__':
    unittest.main()
