"""Check the speaker adapter without changing workstation audio."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ADAPTER = Path(__file__).resolve().parents[1] / "nixos/modules/pc2mqtt-audio.sh"
FAKE = """#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ["AUDIO_FIXTURE"])
s=json.loads(p.read_text()); args=sys.argv[1:]; s["calls"].append(args)
if args[0]=="inspect": print("id 42, type PipeWire:Interface:Node")
elif args[0]=="get-volume": print("Volume: %.2f%s" % (s["volume"], " [MUTED]" if s["muted"] else ""))
elif args[0]=="set-mute": s["muted"]=args[-1]!="0"
elif args[0]=="set-volume":
 if args[1]=="--limit":
  assert args[-1]=="0%+"
  s["volume"]=min(s["volume"],float(args[2]))
 else: s["volume"]=float(args[-1].removesuffix("%"))/100
else: raise AssertionError(args)
p.write_text(json.dumps(s))
"""


class AudioTests(unittest.TestCase):
    def run_adapter(self, operation, volume, muted=True, value="50"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "wpctl"
            helper.write_text(FAKE)
            helper.chmod(0o700)
            state = root / "state.json"
            state.write_text(
                json.dumps({"volume": volume, "muted": muted, "calls": []})
            )
            result = subprocess.run(
                [
                    "bash",
                    "-euo",
                    "pipefail",
                    str(ADAPTER),
                    operation,
                    *([] if operation == "read" else [value]),
                ],
                env={
                    **os.environ,
                    "PATH": str(root) + os.pathsep + os.environ["PATH"],
                    "AUDIO_FIXTURE": str(state),
                },
                capture_output=True,
                text=True,
                check=False,
            )
            return result, json.loads(state.read_text())

    def test_limit_lowers_before_unmuting(self):
        result, state = self.run_adapter("limit-unmute", 0.9)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["volume"], 0.5)
        self.assertFalse(state["muted"])
        actions = [c[0] for c in state["calls"]]
        self.assertLess(actions.index("set-volume"), actions.index("set-mute"))
        self.assertEqual(result.stdout.strip(), "Volume: 0.50")

    def test_limit_never_raises_quiet_output(self):
        for volume in [0, 0.2, 0.5]:
            with self.subTest(volume=volume):
                result, state = self.run_adapter("limit-unmute", volume)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(state["volume"], volume)
                self.assertFalse(state["muted"])

    def test_plain_limit_and_set_preserve_mute(self):
        for operation in ["limit", "set"]:
            result, state = self.run_adapter(operation, 0.8)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(state["muted"])
            self.assertEqual(state["volume"], 0.5)

    def test_read_has_no_side_effects(self):
        result, state = self.run_adapter("read", 0.7)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(state["volume"], 0.7)
        self.assertTrue(state["muted"])
        self.assertTrue(all(c[0] in ["inspect", "get-volume"] for c in state["calls"]))

    def test_bad_commands_cannot_touch_the_output(self):
        for operation, value in [
            ("other", "50"),
            ("set", "101"),
            ("limit", "-1"),
            ("limit", "50;false"),
        ]:
            result, state = self.run_adapter(operation, 0.7, value=value)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(state["calls"], [])


if __name__ == "__main__":
    unittest.main()
