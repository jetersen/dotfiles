"""Plan two native evaluations, then realize and validate one shared build graph."""

import json
import os
from pathlib import Path
import re
import subprocess
import time


STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[^/\s]+")
OUTPUT = re.compile(r"[A-Za-z_][A-Za-z0-9_+-]*")
SHELLS = ("python", "rust", "go", "jvm", "pulumi", "dotnet-preview")


def unique_object(pairs):
  result = {}
  for key, value in pairs:
    if key in result:
      raise ValueError(f"Duplicate JSON key: {key}")
    result[key] = value
  return result


def read_plan(path, count=None):
  rows = json.loads(path.read_text(), object_pairs_hook=unique_object)
  if not isinstance(rows, list) or not rows or (count is not None and len(rows) != count):
    raise ValueError(f"Empty or incomplete plan: {path}")
  for row in rows:
    if not isinstance(row, dict) or not isinstance(row.get("drvPath"), str):
      raise ValueError("Missing derivation path")
    if not STORE.fullmatch(row["drvPath"]) or not row["drvPath"].endswith(".drv"):
      raise ValueError("Invalid derivation path")
    outputs = row.get("outputs")
    if not isinstance(outputs, dict) or not outputs:
      raise ValueError("Empty output selection")
    for name, output in outputs.items():
      if not OUTPUT.fullmatch(name) or not isinstance(output, str) or not STORE.fullmatch(output):
        raise ValueError("Invalid selected output")
  return rows


def selections(rows, *, unique=False):
  selected = {}
  for row in rows:
    for name, output in row["outputs"].items():
      key = (row["drvPath"], name)
      if key in selected and (unique or selected[key] != output):
        raise ValueError("Duplicate or mismatched derivation/output selection")
      selected[key] = output
  return selected


def root(path, target):
  temporary = path.with_name(path.name + ".tmp")
  temporary.unlink(missing_ok=True)
  temporary.symlink_to(target)
  temporary.replace(path)


def cleanup_legacy_roots(roots):
  # Exact names from the former system planner and multi-output Proton build.
  identities = {
    "ci-eval-framework.drv": r"nixos-system-framework-[^/\s]+\.drv",
    "ci-eval-rocket.drv": r"nixos-system-rocket-[^/\s]+\.drv",
    "ci-systems": r"nixos-system-(?:framework|rocket)-[^/\s]+(?<!\.drv)",
    "ci-systems-1": r"nixos-system-(?:framework|rocket)-[^/\s]+(?<!\.drv)",
    "ci-proton-ge-steamcompattool": r"proton-ge-[^/\s]+-steamcompattool",
  }
  for name, identity in identities.items():
    path = roots / name
    if path.is_symlink() and re.fullmatch(r"/nix/store/[a-z0-9]{32}-" + identity, os.readlink(path)):
      path.unlink()


def main():
  temporary = Path(os.environ["RUNNER_TEMP"])
  roots = Path(os.environ.get("CI_GCROOTS", "/nix/var/nix/gcroots"))
  roots.mkdir(parents=True, exist_ok=True)
  # Remove stale manifests if a caller reuses a job directory after a failure.
  manifests = ("framework-system", "rocket-system", "check-outputs", "pc2mqtt-deps", "project-shells")
  for name in manifests:
    (temporary / name).unlink(missing_ok=True)
  discovery_started = time.monotonic()
  names = json.loads(subprocess.check_output([
    "nix", "eval", "--no-update-lock-file", "--json", ".#checks.x86_64-linux",
    "--apply", "builtins.attrNames",
  ]))
  if (not isinstance(names, list) or not names
      or any(not isinstance(name, str) or not OUTPUT.fullmatch(name) for name in names)
      or len(names) != len(set(names))):
    raise ValueError("Invalid or empty check discovery")
  print(f"CI discovery wall={time.monotonic() - discovery_started:.3f}s", flush=True)
  checks = [f'.#checks.x86_64-linux."{name}"' for name in names]
  framework = [".#nixosConfigurations.framework.config.system.build.toplevel", *checks,
               ".#pc2mqtt.cargoArtifacts",
               *(f".#devShells.x86_64-linux.{name}" for name in SHELLS), ".#proton-ge^*"]
  targets = {"framework": framework, "rocket": [".#nixosConfigurations.rocket.config.system.build.toplevel"]}
  processes = []
  started = time.monotonic()
  # Nix 2.35's dry-run emits one entry per installable, in argument order.
  # Keep aliases here; deduplicate only the validated drv/output realization set.
  try:
    for host, installables in targets.items():
      environment = dict(os.environ, XDG_CACHE_HOME=str(
        Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / f"eval-{host}"))
      with (temporary / f"{host}-plan.json").open("w") as output:
        processes.append(subprocess.Popen([
          "nix", "build", *installables, "--no-update-lock-file", "--no-link", "--dry-run", "--json",
        ], stdout=output, env=environment))
  finally:
    # Even a failed planner (or failure starting its peer) must not leak evaluation.
    statuses = [process.wait() for process in processes]
  print(f"CI planning wall={time.monotonic() - started:.3f}s", flush=True)
  if any(statuses):
    raise RuntimeError(f"Native planners failed: {statuses}")
  plans = {host: read_plan(temporary / f"{host}-plan.json", len(items)) for host, items in targets.items()}
  for host, rows in plans.items():
    if f"-nixos-system-{host}-" not in rows[0]["drvPath"] or set(rows[0]["outputs"]) != {"out"}:
      raise ValueError(f"Unexpected {host} system selection")
  if set(plans["framework"][-1]["outputs"]) != {"out", "steamcompattool"}:
    raise ValueError("Incomplete Proton output selection")
  selected = selections([*plans["framework"], *plans["rocket"]])
  for index, drv in enumerate(dict.fromkeys(drv for drv, _ in selected)):
    root(roots / f"ci-eval-{index}.drv", drv)
  installables = [f"{drv}^{name}" for drv, name in selected]
  started = time.monotonic()
  with (temporary / "build-graph.json").open("w") as output:
    subprocess.run([
      "nix", "build", *installables, "--no-update-lock-file", "--max-jobs", "2", "--cores", "4",
      "--out-link", str(roots / "ci-build-graph"), "--json",
    ], stdout=output, check=True)
  print(f"CI realization wall={time.monotonic() - started:.3f}s", flush=True)
  actual = selections(read_plan(temporary / "build-graph.json"), unique=True)
  if actual != selected:
    raise ValueError("Build results differ from the selected derivation/output plan")
  groups = {
    "framework-system": plans["framework"][:1], "rocket-system": plans["rocket"],
    "check-outputs": plans["framework"][1:1 + len(checks)],
    "pc2mqtt-deps": plans["framework"][1 + len(checks):2 + len(checks)],
    "project-shells": plans["framework"][2 + len(checks):-1],
    "proton-ge": plans["framework"][-1:],
  }
  root_names = {"framework-system": "framework", "rocket-system": "rocket",
                "check-outputs": "checks", "pc2mqtt-deps": "pc2mqtt-deps",
                "project-shells": "project-shells", "proton-ge": "proton-ge"}
  for group, rows in groups.items():
    paths = list(dict.fromkeys(selections(rows).values()))
    for index, path in enumerate(paths):
      suffix = "" if index == 0 else f"-{index}"
      root(roots / f"ci-{root_names[group]}{suffix}", path)
    if group in manifests:
      (temporary / group).write_text("".join(path + "\n" for path in paths))

  cleanup_legacy_roots(roots)


if __name__ == "__main__":
  main()
