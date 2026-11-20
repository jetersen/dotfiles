"""Explicit credential/data-directory ownership for an offline migration.

No filenames or login names are used to guess an identity. Prefixes are approved
from private inventory and the selected accounts before freezing the plan.
Unknown files, subdirectories, symlinks and ownership collisions fail closed.
"""
import os
from pathlib import Path, PurePosixPath
import stat

import multinet_state as state


RUNTIME_ONLY = {"multi-profile-host-identities.json"}
NATIVE_LOGS = {"tailscaled.log.conf", "tailscaled.log1.txt", "tailscaled.log2.txt"}


def validate_prefixes(prefixes):
  for relative, owner in prefixes.items():
    path = PurePosixPath(relative)
    state.require(owner in ("personal", "work") and not path.is_absolute() and relative not in ("", ".") and ".." not in path.parts and path.as_posix() == relative, "Invalid credential mapping")
  names = list(prefixes)
  for n, name in enumerate(names):
    state.require(not any(other.startswith(name + "/") or name.startswith(other + "/") for other in names[n + 1:]), "Overlapping credential mappings")


def owner_for(relative, prefixes):
  matches = [owner for prefix, owner in prefixes.items() if relative == prefix or relative.startswith(prefix + "/")]
  state.require(len(matches) == 1, "Unmapped or ambiguous credential dependency")
  return matches[0]


def inventory(root, prefixes, source_owner=None, runtime=False):
  validate_prefixes(prefixes)
  state.require(root.is_dir() and not root.is_symlink() and root.stat().st_uid == os.geteuid() and root.stat().st_mode & 0o077 == 0, "Credential root is not private")
  files = {}
  for current, directories, names in os.walk(root, followlinks=False):
    for name in directories:
      path = Path(current) / name
      info = path.lstat()
      state.require(not path.is_symlink() and info.st_uid == os.geteuid() and info.st_mode & 0o022 == 0, "Unsafe credential directory")
      relative = path.relative_to(root).as_posix()
      # Containers (profile-data/files) may be empty; their children still need
      # an explicit identity mapping before any data is copied.
      if not any(prefix.startswith(relative + "/") for prefix in prefixes):
        owner = owner_for(relative, prefixes)
        state.require(source_owner is None or owner == source_owner, "Credential ownership collision")
    for name in names:
      path = Path(current) / name
      state.require(not path.is_symlink(), "Symlink credential dependency")
      info = path.lstat()
      state.require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and info.st_mode & 0o022 == 0, "Unsafe credential file")
      relative = path.relative_to(root).as_posix()
      if relative == "tailscaled.state" or runtime and relative in RUNTIME_ONLY or source_owner == "work" and relative in NATIVE_LOGS:
        continue
      owner = owner_for(relative, prefixes)
      state.require(source_owner is None or owner == source_owner, "Credential ownership collision")
      files[relative] = {"owner": owner, "payload": state.optional_file(path, private=False)}
  return files


def forward_updates(personal_root, work_root, combined_root, prefixes):
  files = {}
  for owner, root in (("personal", personal_root), ("work", work_root)):
    for relative, entry in inventory(root, prefixes, owner).items():
      target = combined_root / relative
      state.require(target not in files, "Credential destination collision")
      files[target] = entry["payload"]
  return files


def install_forward(updates, guard=state.writers_stopped, write=state.atomic_write):
  guard()
  # Check every existing target first. A running/reused combined var root must
  # never be overwritten with old credentials from an initial snapshot.
  for target, payload in updates.items():
    existing = state.optional_file(target, private=False)
    state.require(existing is None or existing == payload, "Combined credential data is already different")
  for target, payload in updates.items():
    guard()
    state.ensure_private_parents(target.parent)
    if state.optional_file(target, private=False) is None:
      write(target, payload)


def reverse_updates(combined_root, original_roots, baseline, prefixes):
  latest = inventory(combined_root, prefixes, runtime=True)
  updates = {}
  for relative in set(baseline) | set(latest):
    entry = latest.get(relative) or baseline[relative]
    if relative in baseline:
      state.require(entry["owner"] == baseline[relative]["owner"], "Credential ownership changed")
    target = original_roots[entry["owner"]] / relative
    updates[target] = {"payload": latest[relative]["payload"] if relative in latest else None,
                       "before": state.file_hash(baseline[relative]["payload"]) if relative in baseline else None}
  return updates
