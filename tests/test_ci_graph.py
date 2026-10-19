import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "nixos/ci/build-systems.sh"


class BuildGraph(unittest.TestCase):
  def setUp(self):
    self.temporary = tempfile.TemporaryDirectory()
    self.addCleanup(self.temporary.cleanup)
    self.directory = Path(self.temporary.name)
    self.stub = self.directory / "nix"
    self.stub.write_text(f"#!{sys.executable}\n" + '''
import json, os, pathlib, sys, time
args = sys.argv[1:]
base = pathlib.Path(os.environ["RUNNER_TEMP"])
mode = os.environ.get("FIXTURE_MODE", "")
with (base / "commands").open("a") as log:
  log.write(json.dumps(args) + "\\n")
if args[0] == "eval":
  if mode == "discovery-fail": sys.exit(1)
  if mode == "discovery-malformed":
    print("{")
    sys.exit()
  names = {
    "discovery-empty": [], "discovery-shape": {"check": "name"},
    "discovery-invalid": ["bad.name"], "discovery-type": [None],
    "discovery-unhashable": [[]], "discovery-duplicate": ["same", "same"],
  }.get(mode, ["existing", "new-group"])
  print(json.dumps(names))
  sys.exit()
if "--dry-run" in args:
  host = "rocket" if "rocket" in args[1] else "framework"
  if host == "rocket":
    time.sleep(.05)
    (base / "rocket-finished").touch()
  if mode == "fail-" + host:
    sys.exit(1)
  rows = []
  for index, item in enumerate(args[1:args.index("--no-update-lock-file")]):
    name = "nixos-system-" + host + "-fixture" if index == 0 else str(index)
    drv = "/nix/store/" + "a" * 32 + "-" + name + ".drv"
    outputs = {"out": drv[:-4]}
    if item.endswith("^*"):
      outputs["steamcompattool"] = drv[:-4] + "-compat"
    rows.append({"drvPath": drv, "outputs": outputs})
  if host == "framework":
    if mode == "empty": rows = []
    if mode == "missing": rows.pop()
    if mode == "bad-output": rows[-1]["outputs"] = {}
    if mode == "bad-path": rows[1]["drvPath"] = "bad"
    if mode == "proton-missing": del rows[-1]["outputs"]["steamcompattool"]
    if mode == "alias": rows[2] = rows[1]
    if mode == "duplicate-key":
      encoded = json.dumps(rows)
      key = '"drvPath": ' + json.dumps(rows[0]["drvPath"])
      print(encoded.replace(key, key + ", " + key, 1))
      sys.exit()
    if mode == "malformed":
      print("{")
      sys.exit()
  print(json.dumps(rows))
  sys.exit()
(base / "built").touch()
if mode == "fail-manifest": (base / "project-shells").mkdir()
if mode == "fail-check-build": sys.exit(1)
rows = []
for item in args[1:args.index("--no-update-lock-file")]:
  drv, output = item.split("^")
  path = drv[:-4] + ("-compat" if output == "steamcompattool" else "")
  rows.append({"drvPath": drv, "outputs": {output: path}})
if mode == "result-reversed": rows.reverse()
if mode == "result-drv": rows[0]["drvPath"] += "-wrong.drv"
if mode == "result-missing": rows.pop()
if mode == "result-extra": rows.append({"drvPath": "/nix/store/" + "b" * 32 + "-extra.drv", "outputs": {"out": "/nix/store/" + "b" * 32 + "-extra"}})
if mode == "result-mismatch": rows[0]["outputs"]["out"] += "-wrong"
if mode == "result-name": rows[0]["outputs"] = {"wrong": next(iter(rows[0]["outputs"].values()))}
if mode == "result-duplicate": rows.append(rows[0])
print(json.dumps(rows))
''')
    self.stub.chmod(0o755)
    self.environment = {
      **os.environ, "RUNNER_TEMP": str(self.directory),
      "CI_GCROOTS": str(self.directory / "roots"),
      "PATH": str(self.directory) + os.pathsep + os.environ["PATH"],
    }

  def run_graph(self, mode=""):
    return subprocess.run([shutil.which("bash"), str(SCRIPT)],
                          env={**self.environment, "FIXTURE_MODE": mode},
                          capture_output=True, text=True)

  def test_discovered_checks_and_multioutput_proton(self):
    result = self.run_graph()
    self.assertEqual(result.returncode, 0, result.stderr)
    commands = [json.loads(line) for line in (self.directory / "commands").read_text().splitlines()]
    framework = next(args for args in commands if "--dry-run" in args and "framework" in args[1])
    self.assertEqual(framework[1:framework.index("--no-update-lock-file")], [
      ".#nixosConfigurations.framework.config.system.build.toplevel",
      '.#checks.x86_64-linux."existing"', '.#checks.x86_64-linux."new-group"',
      ".#pc2mqtt.cargoArtifacts",
      *(f".#devShells.x86_64-linux.{name}" for name in
        ("python", "rust", "go", "jvm", "pulumi", "dotnet-preview")), ".#proton-ge^*",
    ])
    self.assertEqual(len((self.directory / "check-outputs").read_text().splitlines()), 2)
    self.assertEqual(len((self.directory / "project-shells").read_text().splitlines()), 6)
    self.assertTrue((self.directory / "roots/ci-proton-ge-1").is_symlink())
    self.assertNotIn("compat", (self.directory / "project-shells").read_text())
    built = json.loads((self.directory / "build-graph.json").read_text())
    self.assertEqual(len(built), 13)

  def test_reordered_build_results_are_valid(self):
    result = self.run_graph("result-reversed")
    self.assertEqual(result.returncode, 0, result.stderr)

  def test_shared_alias_is_valid(self):
    result = self.run_graph("alias")
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertEqual(len((self.directory / "check-outputs").read_text().splitlines()), 1)

  def test_failed_planners_are_both_waited(self):
    for mode in ("fail-framework", "fail-rocket"):
      with self.subTest(mode=mode):
        result = self.run_graph(mode)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.directory / "rocket-finished").exists())
        self.assertFalse((self.directory / "built").exists())
        self.assertFalse((self.directory / "framework-system").exists())
        (self.directory / "rocket-finished").unlink()

  def test_invalid_plans_stop_before_realization(self):
    for mode in ("empty", "missing", "malformed", "duplicate-key", "bad-output", "bad-path", "proton-missing"):
      with self.subTest(mode=mode):
        self.assertNotEqual(self.run_graph(mode).returncode, 0)
        self.assertFalse((self.directory / "built").exists())
        self.assertFalse((self.directory / "framework-system").exists())

  def test_build_failure_or_invalid_results_stop_publication(self):
    for mode in ("fail-check-build", "result-missing", "result-extra", "result-mismatch", "result-name", "result-drv", "result-duplicate"):
      with self.subTest(mode=mode):
        # A previous attempt's manifests cannot make a failed retry publishable.
        (self.directory / "framework-system").write_text("stale")
        self.assertNotEqual(self.run_graph(mode).returncode, 0)
        self.assertFalse((self.directory / "framework-system").exists())
        self.assertFalse((self.directory / "roots/ci-framework").exists())

  def test_discovery_failures_stop_before_planning(self):
    for mode in ("empty", "shape", "invalid", "type", "unhashable", "duplicate", "malformed", "fail"):
      with self.subTest(mode=mode):
        for name in ("framework-system", "rocket-system", "check-outputs", "pc2mqtt-deps", "project-shells"):
          (self.directory / name).write_text("stale")
        result = self.run_graph("discovery-" + mode)
        self.assertNotEqual(result.returncode, 0)
        commands = [json.loads(line) for line in (self.directory / "commands").read_text().splitlines()]
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0][0], "eval")
        self.assertFalse(list(self.directory.glob("*-plan.json")))
        self.assertFalse((self.directory / "built").exists())
        for name in ("framework-system", "rocket-system", "check-outputs", "pc2mqtt-deps", "project-shells"):
          self.assertFalse((self.directory / name).exists())
        (self.directory / "commands").unlink()

  def test_duplicate_key_fixture_is_otherwise_valid(self):
    result = self.run_graph("duplicate-key")
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("Duplicate JSON key: drvPath", result.stderr)
    plan = json.loads((self.directory / "framework-plan.json").read_text())
    # Ordinary parsing accepts the fixture and yields the same valid plan.
    self.assertEqual(self.run_graph().returncode, 0)
    self.assertEqual(plan, json.loads((self.directory / "framework-plan.json").read_text()))

  def legacy_roots(self):
    roots = self.directory / "roots"
    roots.mkdir(exist_ok=True)
    targets = {
      "ci-eval-framework.drv": "nixos-system-framework-old.drv",
      "ci-eval-rocket.drv": "nixos-system-rocket-old.drv",
      "ci-systems": "nixos-system-framework-old",
      "ci-systems-1": "nixos-system-rocket-old",
      "ci-proton-ge-steamcompattool": "proton-ge-GE-Proton10-1-steamcompattool",
    }
    for name, target in targets.items():
      (roots / name).symlink_to("/nix/store/" + "a" * 32 + "-" + target)
    return roots, targets

  def test_verified_legacy_roots_removed_after_success(self):
    roots, targets = self.legacy_roots()
    (roots / "ci-systems-2").symlink_to(os.readlink(roots / "ci-systems"))
    (roots / "ci-eval-99.drv").symlink_to(os.readlink(roots / "ci-eval-framework.drv"))
    self.assertEqual(self.run_graph().returncode, 0)
    for name in targets:
      self.assertFalse((roots / name).is_symlink(), name)
    self.assertTrue((roots / "ci-systems-2").is_symlink())
    self.assertTrue((roots / "ci-eval-99.drv").is_symlink())
    self.assertTrue((roots / "ci-framework").is_symlink())
    self.assertTrue((roots / "ci-proton-ge-1").is_symlink())

  def test_unexpected_legacy_roots_preserved(self):
    roots, targets = self.legacy_roots()
    unexpected = ["regular", "directory", "/nix/store/" + "a" * 32 + "-unrelated.drv",
                  "/nix/store/" + "a" * 32 + "-nixos-system-rocket-old.drv",
                  "../proton-ge-old-steamcompattool"]
    for name, target in zip(targets, unexpected):
      path = roots / name
      path.unlink()
      if target == "regular": path.write_text("keep")
      elif target == "directory": path.mkdir()
      else: path.symlink_to(target)
    self.assertEqual(self.run_graph().returncode, 0)
    for name, target in zip(targets, unexpected):
      path = roots / name
      if target == "regular": self.assertEqual(path.read_text(), "keep")
      elif target == "directory": self.assertTrue(path.is_dir())
      else: self.assertEqual(os.readlink(path), target)

  def test_failed_attempts_preserve_legacy_roots(self):
    roots, targets = self.legacy_roots()
    original = {name: os.readlink(roots / name) for name in targets}
    for mode in ("fail-framework", "fail-rocket", "fail-check-build", "result-mismatch"):
      with self.subTest(mode=mode):
        self.assertNotEqual(self.run_graph(mode).returncode, 0)
        self.assertEqual({name: os.readlink(roots / name) for name in targets}, original)

  def test_failed_replacement_preserves_legacy_roots(self):
    roots, targets = self.legacy_roots()
    original = {name: os.readlink(roots / name) for name in targets}
    # A directory prevents atomic replacement of the final managed output root.
    (roots / "ci-proton-ge-1").mkdir()
    self.assertNotEqual(self.run_graph().returncode, 0)
    self.assertEqual({name: os.readlink(roots / name) for name in targets}, original)
    (roots / "ci-proton-ge-1").rmdir()
    # The build fixture blocks a manifest after initial stale-manifest cleanup.
    self.assertNotEqual(self.run_graph("fail-manifest").returncode, 0)
    self.assertEqual({name: os.readlink(roots / name) for name in targets}, original)
