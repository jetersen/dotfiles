import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch


SCRIPT = Path(__file__).resolve().parents[1] / "nixos/ci/build-systems.sh"


SPEC = importlib.util.spec_from_file_location("build_graph", SCRIPT.with_name("build-graph.py"))
graph = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(graph)


def wait_for(path):
  deadline = time.monotonic() + 5
  while not path.exists():
    if time.monotonic() > deadline:
      raise RuntimeError(f"Timed out waiting for {path.name}")
    time.sleep(.001)


def fixture_nix(args, base, mode):
  """One native Nix fixture, callable directly or through its executable wrapper."""
  with (base / "commands").open("a") as log:
    log.write(json.dumps(args) + "\n")
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
    (base / (host + "-started")).touch()
    if os.environ.get("FIXTURE_COORDINATE") == "1":
      peer = "framework-started" if host == "rocket" else "rocket-started"
      wait_for(base / peer)
      if host == "rocket":
        wait_for(base / "release-rocket")
      else:
        (base / "framework-failed").touch()
    if host == "rocket":
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


def fixture_output(args, base, mode):
  output = io.StringIO()
  status = 0
  try:
    with contextlib.redirect_stdout(output):
      fixture_nix(args, base, mode)
  except SystemExit as error:
    status = error.code or 0
  return status, output.getvalue()


class BuildGraph(unittest.TestCase):
  def setUp(self):
    self.temporary = tempfile.TemporaryDirectory()
    self.addCleanup(self.temporary.cleanup)
    self.directory = Path(self.temporary.name)
    self.stub = self.directory / "nix"
    self.stub.write_text(f"#!{sys.executable}\n" +
                         "import pathlib, runpy, os, sys\n" +
                         f"fixture = runpy.run_path({str(Path(__file__).resolve())!r})['fixture_nix']\n" +
                         "fixture(sys.argv[1:], pathlib.Path(os.environ['RUNNER_TEMP']), "
                         "os.environ.get('FIXTURE_MODE', ''))\n")
    self.stub.chmod(0o755)
    self.environment = {
      **os.environ, "RUNNER_TEMP": str(self.directory),
      "CI_GCROOTS": str(self.directory / "roots"),
      "PATH": str(self.directory) + os.pathsep + os.environ["PATH"],
    }

  def run_graph(self, mode="", *, real=False):
    """Four real runs cover CLI wiring, planner waiting, and publication failures."""
    if real:
      command = [shutil.which("bash"), str(SCRIPT)]
      environment = {**self.environment, "FIXTURE_MODE": mode}
      if mode != "fail-framework":
        return subprocess.run(command, env=environment, capture_output=True, text=True, timeout=10)
      # Both planners must start concurrently. Hold Rocket until the failing peer
      # has exited, prove the wrapper is still waiting, then release it.
      with subprocess.Popen(command, env={**environment, "FIXTURE_COORDINATE": "1"},
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
        try:
          wait_for(self.directory / "framework-failed")
          with self.assertRaises(subprocess.TimeoutExpired):
            process.wait(timeout=.05)
        finally:
          (self.directory / "release-rocket").touch()
          stdout, stderr = process.communicate(timeout=10)
      return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

    # Replace only the external Nix boundary. Main still parses real fixture JSON,
    # validates results, and writes real temporary roots and manifests.
    def invoke(args, stdout=None, **kwargs):
      status, output = fixture_output(args[1:], self.directory, mode)
      if stdout is not None:
        stdout.write(output)
      if kwargs.get("check") and status:
        raise subprocess.CalledProcessError(status, args)
      return status, output

    def check_output(args):
      status, output = invoke(args)
      if status:
        raise subprocess.CalledProcessError(status, args)
      return output

    def popen(args, **kwargs):
      status, _ = invoke(args, **kwargs)
      return Mock(wait=Mock(return_value=status))

    output = io.StringIO()
    with patch.dict(os.environ, self.environment), \
         patch.object(graph.subprocess, "check_output", check_output), \
         patch.object(graph.subprocess, "Popen", popen), \
         patch.object(graph.subprocess, "run", invoke), \
         contextlib.redirect_stdout(output):
      try:
        graph.main()
      except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
        return subprocess.CompletedProcess([], 1, output.getvalue(), str(error))
    return subprocess.CompletedProcess([], 0, output.getvalue(), "")

  def test_discovered_checks_and_multioutput_proton(self):
    result = self.run_graph(real=True)
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
    self.assertEqual(len(commands), 4)
    self.assertEqual(commands[0], ["eval", "--no-update-lock-file", "--json",
                                  ".#checks.x86_64-linux", "--apply", "builtins.attrNames"])
    rocket = next(args for args in commands if "--dry-run" in args and "rocket" in args[1])
    self.assertEqual(rocket[1:rocket.index("--no-update-lock-file")],
                     [".#nixosConfigurations.rocket.config.system.build.toplevel"])
    for planner in (framework, rocket):
      self.assertEqual(planner[planner.index("--no-update-lock-file"):],
                       ["--no-update-lock-file", "--no-link", "--dry-run", "--json"])
    realization = next(args for args in commands if args[0] == "build" and "--dry-run" not in args)
    planned = graph.selections([row for host in ("framework", "rocket")
                               for row in graph.read_plan(self.directory / f"{host}-plan.json")])
    self.assertEqual(realization[1:realization.index("--no-update-lock-file")],
                     [f"{drv}^{name}" for drv, name in planned])
    self.assertEqual(realization[realization.index("--no-update-lock-file"):],
                     ["--no-update-lock-file", "--max-jobs", "1", "--cores", "4",
                      "--out-link", str(self.directory / "roots/ci-build-graph"), "--json"])

  def test_reordered_build_results_are_valid(self):
    rows = [{"drvPath": "/nix/store/" + "a" * 32 + "-fixture.drv",
             "outputs": {"out": "/nix/store/" + "a" * 32 + "-fixture"}},
            {"drvPath": "/nix/store/" + "b" * 32 + "-fixture.drv",
             "outputs": {"out": "/nix/store/" + "b" * 32 + "-fixture"}}]
    path = self.directory / "results.json"
    path.write_text(json.dumps(rows[::-1]))
    graph.validate_results(path, graph.selections(rows))
    self.assertEqual(graph.selections([rows[0], rows[0]]), graph.selections(rows[:1]))
    with self.assertRaises(ValueError):
      graph.selections([rows[0], {**rows[0], "outputs": rows[1]["outputs"]}])
    args = ["build", *(f"{drv}^{name}" for drv, name in graph.selections(rows)), "--no-update-lock-file"]
    for mode in ("result-missing", "result-extra", "result-mismatch", "result-name", "result-drv", "result-duplicate"):
      with self.subTest(mode=mode):
        _, output = fixture_output(args, self.directory, mode)
        path.write_text(output)
        with self.assertRaises(ValueError):
          graph.validate_results(path, graph.selections(rows))

  def test_shared_alias_is_valid(self):
    result = self.run_graph("alias")
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertEqual(len((self.directory / "check-outputs").read_text().splitlines()), 1)

  def test_failed_planners_are_both_waited(self):
    for mode in ("fail-framework", "fail-rocket"):
      with self.subTest(mode=mode):
        result = self.run_graph(mode, real=mode == "fail-framework")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.directory / "rocket-finished").exists())
        self.assertFalse((self.directory / "built").exists())
        self.assertFalse((self.directory / "framework-system").exists())
        (self.directory / "rocket-finished").unlink()

  def test_invalid_plans_stop_before_realization(self):
    args = ["build", ".#nixosConfigurations.framework.config.system.build.toplevel",
            '.#checks.x86_64-linux."existing"', ".#proton-ge^*", "--no-update-lock-file", "--dry-run"]
    path = self.directory / "plan.json"
    for mode in ("empty", "missing", "malformed", "duplicate-key", "bad-output", "bad-path"):
      with self.subTest(mode=mode):
        _, output = fixture_output(args, self.directory, mode)
        path.write_text(output)
        with self.assertRaises(ValueError):
          graph.read_plan(path, 3)
    valid = {"drvPath": "/nix/store/" + "a" * 32 + "-fixture.drv",
             "outputs": {"out": "/nix/store/" + "a" * 32 + "-fixture"}}
    for rows in ({}, [None], [{}], [{**valid, "drvPath": None}],
                 [{**valid, "outputs": []}], [{**valid, "outputs": {"bad.name": "bad"}}],
                 [{**valid, "outputs": {"out": None}}]):
      with self.subTest(rows=rows):
        path.write_text(json.dumps(rows))
        with self.assertRaises(ValueError):
          graph.read_plan(path)
    # The complete Proton output contract is checked by orchestration itself.
    self.assertNotEqual(self.run_graph("proton-missing").returncode, 0)
    self.assertFalse((self.directory / "built").exists())
    self.assertFalse((self.directory / "framework-system").exists())

  def test_build_failure_or_invalid_results_stop_publication(self):
    for mode in ("fail-check-build", "result-mismatch"):
      with self.subTest(mode=mode):
        # A previous attempt's manifests cannot make a failed retry publishable.
        (self.directory / "framework-system").write_text("stale")
        self.assertNotEqual(self.run_graph(mode, real=True).returncode, 0)
        self.assertFalse((self.directory / "framework-system").exists())
        self.assertFalse((self.directory / "roots/ci-framework").exists())

  def test_discovery_failures_stop_before_planning(self):
    for names in ([], {"check": "name"}, ["bad.name"], [None], [[]], ["same", "same"]):
      with self.subTest(names=names), self.assertRaises(ValueError):
        graph.check_installables(names)
    self.assertEqual(graph.check_installables(["existing", "new-group"]),
                     ['.#checks.x86_64-linux."existing"', '.#checks.x86_64-linux."new-group"'])
    for mode in ("empty", "malformed", "fail"):
      with self.subTest(mode=mode):
        manifests = ("framework-system", "rocket-system", "check-outputs", "pc2mqtt-deps", "project-shells")
        for name in manifests:
          (self.directory / name).write_text("stale")
        self.assertNotEqual(self.run_graph("discovery-" + mode).returncode, 0)
        commands = [json.loads(line) for line in (self.directory / "commands").read_text().splitlines()]
        self.assertEqual(len(commands), 1)
        self.assertEqual(commands[0][0], "eval")
        self.assertFalse(list(self.directory.glob("*-plan.json")))
        self.assertFalse((self.directory / "built").exists())
        for name in manifests:
          self.assertFalse((self.directory / name).exists())
        (self.directory / "commands").unlink()

  def test_duplicate_key_fixture_is_otherwise_valid(self):
    args = ["build", ".#nixosConfigurations.framework.config.system.build.toplevel",
            ".#proton-ge^*", "--no-update-lock-file", "--dry-run"]
    path = self.directory / "plan.json"
    _, duplicate = fixture_output(args, self.directory, "duplicate-key")
    _, valid = fixture_output(args, self.directory, "")
    self.assertEqual(json.loads(duplicate), json.loads(valid))
    path.write_text(duplicate)
    with self.assertRaisesRegex(ValueError, "Duplicate JSON key: drvPath"):
      graph.read_plan(path)

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
