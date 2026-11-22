from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest


WRAPPER = Path(__file__).resolve().parents[1] / "nixos/home/wayland-clipboard.sh"


class DesktopEnvironmentTests(unittest.TestCase):
    def run_wrapper(self, environment, session='{"WAYLAND_DISPLAY":"wayland-1","PATH":"desktop-path"}'):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls = root / "calls"
            systemctl = root / "systemctl"
            systemctl.write_text(f'#!{shutil.which("bash")}\n' + '''
printf '%s\\n' "$XDG_RUNTIME_DIR" > "$TEST_CALLS"
printf '%s\\n' "$TEST_SESSION"
''')
            systemctl.chmod(0o700)
            path = f'{root}{os.pathsep}{os.environ["PATH"]}'
            result = subprocess.run(
                ["bash", WRAPPER, sys.executable, "-c",
                 "import json, os, sys; print(json.dumps([dict(os.environ), sys.argv[1:]]))",
                 "--primary", "argument with spaces"],
                env={"PATH": path, "TEST_CALLS": str(calls), "TEST_SESSION": session, **environment},
                check=True, capture_output=True, text=True,
            )
            env, arguments = json.loads(result.stdout)
            self.assertEqual(arguments, ["--primary", "argument with spaces"])
            self.assertEqual(env["PATH"], path)
            return env, calls.read_text().strip() if calls.exists() else None

    def test_remote_session_recovers_desktop(self):
        env, queried = self.run_wrapper({})
        runtime = f"/run/user/{os.getuid()}"
        self.assertEqual(queried, runtime)
        self.assertEqual(env["XDG_RUNTIME_DIR"], runtime)
        self.assertEqual(env["WAYLAND_DISPLAY"], "wayland-1")

    def test_existing_desktop_is_untouched(self):
        original = {"WAYLAND_DISPLAY": "custom", "XDG_RUNTIME_DIR": "/custom"}
        env, queried = self.run_wrapper(original)
        self.assertIsNone(queried)
        self.assertEqual({key: env[key] for key in original}, original)

    def test_partial_environment_preserves_display(self):
        env, queried = self.run_wrapper({"WAYLAND_DISPLAY": "custom"})
        self.assertIsNone(queried)
        self.assertEqual(env["WAYLAND_DISPLAY"], "custom")
        self.assertEqual(env["XDG_RUNTIME_DIR"], f"/run/user/{os.getuid()}")

    def test_no_desktop_leaves_diagnostics_to_wl_clipboard(self):
        env, _ = self.run_wrapper({}, session="invalid JSON")
        self.assertNotIn("WAYLAND_DISPLAY", env)
