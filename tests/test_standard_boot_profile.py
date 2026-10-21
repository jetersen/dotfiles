"""Exercise the production hook with real nix-env and isolated profiles."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from types import SimpleNamespace


SOURCE = Path(__file__).absolute().parents[1] / "nixos/modules/standard-boot-profile.py"
spec = importlib.util.spec_from_file_location("boot_profile", SOURCE)
boot_profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot_profile)


class StandardBootProfileTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="standard-boot-profile-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.targets = [Path(os.environ[f"BOOT_TEST_SYSTEM_{i}"]) for i in range(4)]
        self.profile = self.root / "system"
        self.comin = self.root / "named/comin"
        self.comin.parent.mkdir()
        self.booted = self.root / "booted"
        self.booted.symlink_to(self.targets[0])
        self.log = self.root / "installer.json"
        installer = self.root / "installer"
        installer.write_text(
            f"#!{os.environ['BOOT_TEST_PYTHON']}\n"
            "import json, pathlib, sys\n"
            f"p = pathlib.Path({str(self.profile)!r})\n"
            f"pathlib.Path({str(self.log)!r}).write_text(json.dumps(\n"
            "    {'target': sys.argv[1], 'selected': str(p.resolve()), 'args': sys.argv[2:]}))\n"
            f"sys.exit(23 if pathlib.Path({str(self.root / 'fail')!r}).exists() else 0)\n"
        )
        installer.chmod(0o755)
        self.args = SimpleNamespace(
            target=self.targets[1],
            profile=self.profile,
            comin=self.comin,
            booted=self.booted,
            state=self.root / "state",
            nix_env=os.environ["BOOT_TEST_NIX_ENV"],
            installer=str(installer),
            installer_args=["argument with spaces"],
        )

    def nix(self, profile, *args):
        subprocess.run([self.args.nix_env, "--profile", str(profile), *args], check=True)

    def deploy(self, target):
        self.nix(self.comin, "--set", str(target))
        self.args.target = target
        boot_profile.install(self.args)

    def owned(self):
        return json.loads((self.args.state / "generations.json").read_text())

    def test_requested_boot_target_precedes_installer_and_repeat_is_idempotent(self):
        self.nix(self.profile, "--set", str(self.targets[0]))
        self.deploy(self.targets[1])
        self.assertEqual(self.profile.resolve(), self.targets[1])
        self.assertEqual(self.booted.resolve(), self.targets[0])
        self.assertEqual(json.loads(self.log.read_text()), {
            "target": str(self.targets[1]), "selected": str(self.targets[1]),
            "args": ["argument with spaces"],
        })
        before = boot_profile.generations(self.profile)
        self.deploy(self.targets[1])
        self.assertEqual(boot_profile.generations(self.profile), before)
        self.assertEqual(set(self.owned()), {"2"})

    def test_comin_retention_prunes_owned_mirrors_and_preserves_manual_and_booted(self):
        self.nix(self.profile, "--set", str(self.targets[3]))  # Manual history.
        self.deploy(self.targets[0])
        self.deploy(self.targets[1])
        self.deploy(self.targets[2])
        self.nix(self.comin, "--delete-generations", "1", "2")
        # Previous standard selection is protected until another successful boot target exists.
        self.deploy(self.targets[2])
        generations = boot_profile.generations(self.profile)
        self.assertEqual(set(generations), {"1", "2", "4"})
        self.assertEqual(generations["1"]["target"], str(self.targets[3]))
        self.assertEqual(generations["2"]["target"], str(self.targets[0]))
        self.assertEqual(set(boot_profile.generations(self.comin)), {"3"})

    def test_manual_generations_are_not_claimed(self):
        self.nix(self.comin, "--set", str(self.targets[1]))
        self.nix(self.profile, "--set", str(self.targets[1]))
        boot_profile.install(self.args)
        self.assertEqual(self.owned(), {})

    def test_reused_manual_generation_number_is_not_deleted(self):
        self.deploy(self.targets[1])
        self.deploy(self.targets[2])
        link = self.root / "system-1-link"
        link.unlink()
        link.symlink_to(self.targets[3])
        self.nix(self.comin, "--delete-generations", "1")
        self.deploy(self.targets[2])
        self.assertEqual(link.resolve(), self.targets[3])
        self.assertNotIn("1", self.owned())

    def test_installer_failure_propagates_and_restores_previous_selection(self):
        self.deploy(self.targets[0])
        (self.root / "fail").touch()
        with self.assertRaises(subprocess.CalledProcessError) as failure:
            self.deploy(self.targets[1])
        self.assertEqual(failure.exception.returncode, 23)
        self.assertEqual(self.profile.resolve(), self.targets[0])
        self.assertEqual(set(boot_profile.generations(self.profile)), {"1", "2"})
        self.assertEqual(set(self.owned()), {"1", "2"})

    def test_manual_rollback_is_registered_as_latest_for_lanzaboote(self):
        self.deploy(self.targets[0])
        self.deploy(self.targets[1])
        self.nix(self.profile, "--switch-generation", "1")
        self.args.target = self.targets[0]
        boot_profile.install(self.args)
        self.assertEqual(os.readlink(self.profile), "system-3-link")
        self.assertEqual(self.profile.resolve(), self.targets[0])

    def test_invalid_target_and_nix_failure_never_run_installer(self):
        self.args.target = self.root
        with self.assertRaises(ValueError):
            boot_profile.install(self.args)
        self.assertFalse(self.log.exists())
        self.assertFalse(self.profile.exists())
        self.args.target = self.targets[1]
        self.args.nix_env = "/nonexistent/nix-env"
        with self.assertRaises(FileNotFoundError):
            boot_profile.install(self.args)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
