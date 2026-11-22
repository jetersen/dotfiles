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

def generate_shortcodes(entries, custom):
    with tempfile.TemporaryDirectory() as directory:
        overrides = Path(directory) / "custom.json"
        overrides.write_text(json.dumps(custom))
        program = ROOT / "nixos/packages/emoji-shortcodes.jq"
        return subprocess.run(
            ["jq", "--slurpfile", "custom", overrides, "-f", program],
            input=json.dumps(entries), text=True, capture_output=True,
        )


class EmojiExpansionTests(unittest.TestCase):
    def test_custom_sequences_and_alias_overrides(self):
        result = generate_shortcodes(
            [{"emoji": "👏", "aliases": ["clap"]}, {"emoji": "✈️", "aliases": ["airplane"]}],
            {"ship_it": "🚢🚀", "clap": "👏🎉", "flight": "✈"},
        )
        result.check_returncode()
        output = json.loads(result.stdout)
        self.assertEqual(output["matches"], [
            {"trigger": ":airplane:", "replace": "✈️"},
            {"trigger": ":clap:", "replace": "👏🎉"},
            {"trigger": ":flight:", "replace": "✈"},
            {"trigger": ":ship_it:", "replace": "🚢🚀"},
        ])
        self.assertEqual(output["byEmoji"]["✈"], ["airplane", "flight"])
        self.assertEqual(output["customEntries"][-1], {
            "emoji": "✈", "name": "airplane", "keywords": ["airplane", "flight"], "category": "custom",
        })
        self.assertNotIn("shipit", output["shortcodes"])

    def test_invalid_aliases_and_conflicts_fail(self):
        self.assertNotEqual(generate_shortcodes([], {":bad:": "🙂"}).returncode, 0)
        self.assertNotEqual(generate_shortcodes([], {"bad": " "}).returncode, 0)
        self.assertNotEqual(generate_shortcodes([
            {"emoji": "👏", "aliases": ["duplicate"]},
            {"emoji": "✈️", "aliases": ["duplicate"]},
        ], {}).returncode, 0)

    def test_layout_snapshot_switch_and_unrelated_events(self):
        codes = layout.layout_codes((ROOT / 'nixos/assets/config/niri/cfg/input.kdl').read_text())
        self.assertEqual(codes, ['us', 'dk'])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'espanso-niri'
            (root / 'config').mkdir(parents=True)
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
            self.assertTrue(settings['enable'])
            (root.parent / 'espanso-picker/resume').touch()
            layout.watch(root, codes, io.StringIO('{"KeyboardLayoutSwitched": {"idx": 1}}\n'), lambda: None)
            settings = json.loads(target.read_text())
            self.assertEqual(settings['keyboard_layout'], {'layout': 'dk'})
            self.assertFalse(settings['enable'], 'a keymap reload must not enable expansion in the picker')

    def run_control(self, directory, action):
        return subprocess.run(['bash', '-euo', 'pipefail',
                               str(ROOT / 'nixos/home/emoji-expansion-control.sh'), action],
                              env=dict(os.environ, XDG_RUNTIME_DIR=directory,
                                       PATH=directory + os.pathsep + os.environ['PATH']),
                              check=True)

    def test_picker_disables_and_enables_without_restarting_or_rewriting_config(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fake = root / 'systemctl'
            fake.write_text(f'#!{shutil.which("bash")}\n' + '''set -eu
cd "$XDG_RUNTIME_DIR"
case "$2" in
 is-active) test -f active ;;
 *) echo 'service restart is forbidden' >&2; exit 99 ;;
esac
''')
            fake.chmod(0o700)
            fake = root / 'espanso'
            fake.write_text(f'#!{shutil.which("bash")}\n' + '''set -eu
cd "$XDG_RUNTIME_DIR"
test "$1" = cmd
test -f active
test ! -f fail-command
echo "$2" >> calls
''')
            fake.chmod(0o700)
            config = root / 'espanso-niri/config/default.yml'
            config.parent.mkdir(parents=True)
            config.write_text(json.dumps({'enable': True, 'keyboard_layout': {'layout': 'us'}}))
            unchanged = config.stat().st_mtime_ns
            self.run_control(directory, 'pause')
            self.run_control(directory, 'resume')
            self.assertFalse((root / 'calls').exists(), 'do not enable a previously stopped service')
            (root / 'active').touch()
            self.run_control(directory, 'pause')
            self.run_control(directory, 'pause')
            self.assertTrue((root / 'active').exists(), 'the daemon must keep running')
            self.run_control(directory, 'resume')
            self.run_control(directory, 'resume')
            self.assertTrue((root / 'active').exists())
            self.assertEqual((root / 'calls').read_text().splitlines(), ['disable', 'enable'])
            self.assertEqual(config.stat().st_mtime_ns, unchanged, 'normal picks must not trigger a worker reload')
            self.run_control(directory, 'pause')
            (root / 'fail-command').touch()
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_control(directory, 'resume')
            self.assertTrue((root / 'espanso-picker/resume').exists(), 'failed resume must remain retryable')
            (root / 'fail-command').unlink()
            # A layout switch may persist a disabled default while paused.
            config.write_text(json.dumps({'enable': False, 'keyboard_layout': {'layout': 'dk'}}))
            self.run_control(directory, 'resume')
            self.assertEqual(json.loads(config.read_text()),
                             {'enable': True, 'keyboard_layout': {'layout': 'dk'}})
            # Explicitly stopping Espanso during a pause must not start it on close.
            self.run_control(directory, 'pause')
            (root / 'active').unlink()
            self.run_control(directory, 'resume')
            self.assertFalse((root / 'active').exists())


if __name__ == '__main__':
    unittest.main()
