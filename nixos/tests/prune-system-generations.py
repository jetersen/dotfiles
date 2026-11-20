import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "prune", Path(__file__).resolve().parents[1] / "modules/prune-system-generations.py"
)
prune = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prune)
DAY = 86400
NOW = 100 * DAY


class RetentionTests(unittest.TestCase):
    def test_retention(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            targets = []
            for n in range(1, 13):
                target = root / f"closure-{n}"
                target.mkdir()
                targets.append(target)
                link = root / f"system-{n}-link"
                link.symlink_to(target)
                age = 2 if n == 6 else 8
                os.utime(link, (NOW - age * DAY,) * 2, follow_symlinks=False)
            # Old booted generation, rolled-back current, and staged system survive.
            protected = {targets[0], targets[1], targets[2]}
            self.assertEqual(
                prune.expired_generations(root / "system", protected, NOW), [7, 5, 4]
            )
            # Repeated selection is stable and unrelated profile links are ignored.
            (root / "home-manager-1-link").symlink_to(targets[0])
            self.assertEqual(
                prune.expired_generations(root / "system", protected, NOW), [7, 5, 4]
            )

    def test_fewer_than_five(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for n in range(1, 5):
                link = root / f"system-{n}-link"
                link.symlink_to(root)
                os.utime(link, (0, 0), follow_symlinks=False)
            self.assertEqual(prune.expired_generations(root / "system", set(), NOW), [])

    def test_broken_generation_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for n in range(1, 7):
                link = root / f"system-{n}-link"
                link.symlink_to(root / "missing")
                os.utime(link, (0, 0), follow_symlinks=False)
            with self.assertRaises(FileNotFoundError):
                prune.expired_generations(root / "system", set(), NOW)


if __name__ == "__main__":
    unittest.main()
