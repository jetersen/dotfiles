"""Merge declared search settings without exposing or discarding private settings."""

from collections.abc import Mapping

import argparse
import os
from pathlib import Path

import tomlkit


def merge(existing, declared):
  for key, value in declared.items():
    if isinstance(value, Mapping):
      if key not in existing or not isinstance(existing[key], Mapping):
        existing[key] = tomlkit.table()
      merge(existing[key], value)
    else:
      existing[key] = value
  return existing


def configure(target, template):
  current = target.read_text() if target.exists() else ""
  merged = tomlkit.dumps(merge(tomlkit.parse(current), tomlkit.parse(template.read_text())))
  if current == merged:
    return
  target.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
  temporary = target.with_suffix(".nix-tmp")
  with temporary.open("w") as output:
    os.chmod(temporary, 0o600)
    output.write(merged)
  temporary.replace(target)


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--target", type=Path, required=True)
  parser.add_argument("--template", type=Path, required=True)
  parser.add_argument("--mountpoint", type=Path, required=True)
  args = parser.parse_args()
  if not os.path.ismount(args.mountpoint):
    raise RuntimeError("Search data filesystem must be mounted before configuration")
  try:
    configure(args.target, args.template)
  except Exception:
    raise SystemExit("Unable to merge agent settings; existing private configuration was not displayed") from None


if __name__ == "__main__":
  main()
