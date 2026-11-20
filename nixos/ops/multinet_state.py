"""Offline, credential-preserving Rocket state conversion for the private core.

The contract is pinned to the 37f739c58 v3 procedure.
Callers must freeze private snapshots and directory mappings, stop all writers,
verify the packaged core and arm independent rollback before using the outputs.
This module neither enrolls nodes nor starts services. State values never appear
in errors. Production snapshots/plans/staging belong outside git and Nix stores.
"""

import base64
import copy
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import tempfile
import time


DEFAULT_REALM = "https://controlplane.tailscale.com"
IMPORTED = "_imported-machinekey"
OPERATIONAL = {"personal": ("CorpDNS",), "work": ("CorpDNS", "OperatorUser", "WantRunning")}
WRITERS = ("tailscaled", "tailscaled-work", "tailscale-multi-profile", "work-tailnet")


class MigrationError(Exception):
  """A deliberately non-sensitive operator error."""


def require(condition, message):
  if not condition:
    raise MigrationError(message)


def unique_object(pairs):
  result = {}
  for key, value in pairs:
    require(key not in result, "Duplicate JSON member")
    result[key] = value
  return result


def json_value(data):
  try:
    def invalid_constant(_):
      raise MigrationError("Non-JSON numeric constant")
    return json.loads(data, object_pairs_hook=unique_object, parse_constant=invalid_constant)
  except (ValueError, UnicodeError, TypeError):
    raise MigrationError("Invalid JSON; encrypted or corrupt input is unsupported") from None


def json_bytes(value):
  return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def digest(data):
  return hashlib.sha256(data).hexdigest()


def decode_store(data):
  outer = json_value(data)
  require(isinstance(outer, dict), "State must be an object")
  try:
    require(all(isinstance(k, str) and isinstance(v, str) for k, v in outer.items()), "Invalid state entry")
    return {k: base64.b64decode(v, validate=True) for k, v in outer.items()}
  except (ValueError, TypeError):
    raise MigrationError("Invalid state encoding") from None


def encode_store(store):
  return json_bytes({k: base64.b64encode(v).decode() for k, v in store.items()}) + b"\n"


def realm(value):
  require(isinstance(value, str), "Invalid control realm")
  return DEFAULT_REALM if value in ("", DEFAULT_REALM, "https://login.tailscale.com") else value


def private_key(value):
  require(isinstance(value, str) and re.fullmatch(r"privkey:[0-9a-fA-F]{64}", value) is not None, "Invalid private key encoding")
  raw = bytes.fromhex(value[8:])
  require(any(raw), "Zero private key")
  return raw


def created_ns(value):
  if value in (None, "", "0001-01-01T00:00:00Z"):
    return 0
  require(isinstance(value, str), "Invalid profile creation time")
  match = re.fullmatch(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,9}))?(Z|[+-]\d\d:\d\d)", value)
  require(match is not None, "Invalid profile creation time")
  try:
    stamp = datetime.fromisoformat(match[1] + match[3].replace("Z", "+00:00"))
    require(1970 <= stamp.year <= 2261, "Unsupported profile creation time")
    delta = stamp - datetime(1970, 1, 1, tzinfo=timezone.utc)
    seconds = delta.days * 86400 + delta.seconds
    return seconds * 10**9 + int((match[2] or "").ljust(9, "0"))
  except ValueError:
    raise MigrationError("Invalid profile creation time") from None


def new_created():
  ns = time.time_ns()
  fraction = f"{ns % 10**9:09d}".rstrip("0")
  return datetime.fromtimestamp(ns // 10**9, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S") + ("." + fraction if fraction else "") + "Z"


def catalog(store):
  require("_profiles" in store, "Missing profile catalog")
  profiles = json_value(store["_profiles"])
  require(isinstance(profiles, dict), "Invalid profile catalog")
  seen = set()
  for pid, profile in profiles.items():
    require(isinstance(profile, dict) and profile.get("ID") == pid, "Catalog identity mismatch")
    key = profile.get("Key")
    require(isinstance(key, str) and key.startswith("profile-") and "||" not in key and key not in seen, "Ambiguous profile key")
    seen.add(key)
  return profiles


def selected(store, pid, node):
  profiles = catalog(store)
  require(pid in profiles, "Selected profile is missing")
  profile = profiles[pid]
  key = profile["Key"]
  require(key in store, "Selected preferences are missing")
  prefs = json_value(store[key])
  require(isinstance(prefs, dict) and "Persist" not in prefs and isinstance(prefs.get("Config"), dict), "Missing or ambiguous Config credentials")
  for field, kind in (("CorpDNS", bool), ("WantRunning", bool), ("RouteAll", bool), ("OperatorUser", str)):
    require(field not in prefs or type(prefs[field]) is kind, "Invalid operational preference type")
  require(profile.get("NodeID") == node == prefs["Config"].get("NodeID"), "Stable node identity mismatch")
  private_key(prefs["Config"].get("PrivateNodeKey"))
  for field, prefix, length in (("OldPrivateNodeKey", "privkey:", 64), ("NetworkLockKey", "nlpriv:", 128)):
    value = prefs["Config"].get(field)
    require(value in (None, "") or isinstance(value, str) and re.fullmatch(re.escape(prefix) + r"[0-9a-fA-F]{" + str(length) + "}", value) is not None, "Invalid persisted private key encoding")
  require(realm(profile.get("ControlURL", "")) == realm(prefs.get("ControlURL", "")), "Control realm mismatch")
  require("_machinekey" in store, "Missing machine key")
  try:
    machine = store["_machinekey"].decode()
  except UnicodeError:
    raise MigrationError("Invalid machine key encoding") from None
  private_key(machine)
  return profile, prefs, machine


def binding(profile):
  return {"id": profile["ID"], "key": profile["Key"], "node": profile["NodeID"],
          "realm": realm(profile.get("ControlURL", "")), "created": created_ns(profile.get("Created"))}


def native_values(prefs, label):
  return {k: {"present": k in prefs, "value": prefs.get(k)} for k in OPERATIONAL[label]}


def make_plan(personal, work, native_personal=None, native_work=None, work_created=None):
  """Use pre-stop native prefs but final quiesced credentials as the source."""
  plan = {"version": 1, "contract": "37f739c58-v3", "sources": {}, "workMapping": {}}
  for label, store, native, pid, node in (
    ("personal", personal, personal if native_personal is None else native_personal, "4322", "nLsFQzqjmq11CNTRL"),
    ("work", work, work if native_work is None else native_work, "b57d", "nYGBXVi8Wv11CNTRL"),
  ):
    profile, prefs, machine = selected(store, pid, node)
    before, native_prefs, native_machine = selected(native, pid, node)
    require(binding(before) == binding(profile) and private_key(native_machine) == private_key(machine), "Pre-stop identity differs from quiesced state")
    require(prefs.get("RouteAll") == native_prefs.get("RouteAll"), "Native routing preference changed during quiesce")
    require(store.get("_current-profile") == profile["Key"].encode(), "Unexpected native profile selection")
    require(not any(k.startswith("_profile-network") for k in store), "Native input already has experimental selection")
    plan["sources"][label] = {
      "binding": binding(profile), "sourceHash": digest(encode_store(store)),
      "machineHash": digest(private_key(machine)), "nativeOperational": native_values(native_prefs, label),
      "routeAll": prefs.get("RouteAll"),
    }
  require(plan["sources"]["personal"]["machineHash"] != plan["sources"]["work"]["machineHash"], "Expected two independent machine identities")
  profile = catalog(work)["b57d"]
  created = profile.get("Created") if created_ns(profile.get("Created")) else (work_created or new_created())
  require(created_ns(created) != 0, "Imported profile requires a creation generation")
  plan["workCreated"] = created
  plan["personalServeHash"] = digest(personal.get("_serve/4322", b""))
  return plan


def validate_sources(personal, work, plan):
  require(plan.get("version") == 1 and plan.get("contract") == "37f739c58-v3", "Unexpected migration plan")
  require(created_ns(plan.get("workCreated")) != 0, "Imported generation is missing")
  require(plan["sources"]["personal"]["binding"]["id"] == "4322" and plan["sources"]["work"]["binding"]["id"] == "b57d", "Unexpected selected profile pair")
  for label, store in (("personal", personal), ("work", work)):
    expected = plan["sources"][label]
    require(set(expected["nativeOperational"]) == set(OPERATIONAL[label]), "Unexpected native operational override")
    require(all(isinstance(v, dict) and type(v.get("present")) is bool for v in expected["nativeOperational"].values()), "Invalid native preference baseline")
    profile, _, machine = selected(store, expected["binding"]["id"], expected["binding"]["node"])
    require(binding(profile) == expected["binding"] and digest(private_key(machine)) == expected["machineHash"], "Source identity or generation changed")
    require(digest(encode_store(store)) == expected["sourceHash"], "Source snapshot changed")
  if plan["workMapping"]:
    profile = catalog(work)["b57d"]
    expected_mapping = {target: key for key in work if (target := work_destination(key, profile)) is not None}
    require(plan["workMapping"] == expected_mapping, "Original scoped mapping changed")


def work_destination(key, profile):
  own = profile["Key"]
  if key in ("_profiles", "_machinekey", "_current-profile", "server-mode-start-key", "_daemon") or key.startswith(("_current/", "_profile-network")):
    return None
  require(key not in (IMPORTED, own + "||" + IMPORTED), "Native source contains imported authority")
  if key == own or key.startswith(own + "||"):
    return key
  if key.startswith("profile-") or key.startswith("_serve/") and key != "_serve/" + profile["ID"]:
    return None
  return own + "||" + key


def forward(personal, work, plan):
  validate_sources(personal, work, plan)
  result = dict(personal)
  profiles = copy.deepcopy(catalog(personal))
  work_profile, work_prefs, machine = selected(work, "b57d", plan["sources"]["work"]["binding"]["node"])
  require("b57d" not in profiles and work_profile["Key"] not in {p["Key"] for p in profiles.values()}, "Catalog collision")
  imported = copy.deepcopy(work_profile)
  imported["Created"] = plan["workCreated"]
  profiles["b57d"] = imported
  mapping = {}
  for key, value in work.items():
    target = work_destination(key, work_profile)
    if target is None:
      continue
    require(target not in result and target not in mapping, "State key collision")
    result[target] = value
    mapping[target] = key
  if plan["workMapping"]:
    require(plan["workMapping"] == mapping, "Retry mapping differs")
  plan["workMapping"] = mapping
  result["_profiles"] = json_bytes(profiles)
  own = imported["Key"]
  result[own + "||" + IMPORTED] = json_bytes({
    "Version": 1, "Profile": "b57d", "Created": plan["workCreated"], "NodeID": imported["NodeID"],
    "ControlURL": realm(imported.get("ControlURL", "")), "MachineKey": machine,
  })
  work_prefs = copy.deepcopy(work_prefs)
  work_prefs.update(CorpDNS=True, OperatorUser="joseph", WantRunning=True)
  result[own] = json_bytes(work_prefs)
  personal_key = profiles["4322"]["Key"]
  personal_prefs = json_value(personal[personal_key])
  personal_prefs["CorpDNS"] = True
  result[personal_key] = json_bytes(personal_prefs)
  selection_key = "_profile-network-4322-" + format(created_ns(profiles["4322"].get("Created")), "x")
  require(selection_key not in result, "Selection key collision")
  result[selection_key] = json_bytes({"primary": "4322", "secondary": ["b57d"], "preferred": "4322"})
  require(result["_machinekey"] == personal["_machinekey"] and result["_current-profile"] == personal["_current-profile"], "Personal authority changed")
  require(digest(result.get("_serve/4322", b"")) == plan["personalServeHash"], "Personal Serve changed")
  return result


def latest_identity(latest, plan):
  personal = plan["sources"]["personal"]
  work = plan["sources"]["work"]
  for label, expected in (("personal", personal), ("work", work)):
    profile, _, _ = selected(latest, expected["binding"]["id"], expected["binding"]["node"])
    wanted = dict(expected["binding"])
    if label == "work":
      wanted["created"] = created_ns(plan["workCreated"])
    require(binding(profile) == wanted, "Latest catalog identity/generation changed")
  own = work["binding"]["key"]
  require(own + "||" + IMPORTED in latest, "Imported authority missing")
  record = json_value(latest[own + "||" + IMPORTED])
  require(isinstance(record, dict) and type(record.get("Version")) is int and record["Version"] == 1, "Invalid imported authority")
  require(record.get("Profile") == "b57d" and record.get("NodeID") == work["binding"]["node"] and created_ns(record.get("Created")) == created_ns(plan["workCreated"]) and realm(record.get("ControlURL", "")) == work["binding"]["realm"], "Imported authority binding changed")
  require(digest(private_key(record.get("MachineKey"))) == work["machineHash"], "Imported machine identity changed")
  try:
    machine = latest["_machinekey"].decode()
  except (KeyError, UnicodeError):
    raise MigrationError("Personal machine identity missing") from None
  require(digest(private_key(machine)) == personal["machineHash"], "Personal machine identity changed")
  require(latest.get("_current-profile") == personal["binding"]["key"].encode(), "Latest personal selection changed")


def restore_operational(prefs, values):
  result = copy.deepcopy(prefs)
  for key, saved in values.items():
    if saved["present"]:
      result[key] = saved["value"]
    else:
      result.pop(key, None)
  return result


def reverse(latest, personal, work, plan):
  validate_sources(personal, work, plan)
  require(bool(plan["workMapping"]), "Original scoped mapping is missing")
  latest_identity(latest, plan)
  own = plan["sources"]["work"]["binding"]["key"]
  parent = plan["sources"]["personal"]["binding"]["key"]
  require(json_value(latest[parent]).get("RouteAll") == plan["sources"]["personal"]["routeAll"], "Personal LAN routing preference changed")
  before_catalog = catalog(personal)
  after_catalog = catalog(latest)
  require(set(after_catalog) == set(before_catalog) | {"b57d"}, "Unexpected catalog membership change")
  for pid, profile in before_catalog.items():
    if pid != "4322":
      require(after_catalog[pid] == profile, "Unselected catalog changed")
      require(profile["Key"] in latest, "Unselected credentials disappeared")
  native_personal = {k: v for k, v in latest.items() if k != own and not k.startswith(own + "||") and not k.startswith("_profile-network")}
  restored_catalog = copy.deepcopy(before_catalog)
  restored_catalog["4322"] = after_catalog["4322"]
  native_personal["_profiles"] = json_bytes(restored_catalog)
  native_personal["_machinekey"] = personal["_machinekey"]
  native_personal["_current-profile"] = personal["_current-profile"]
  native_personal[parent] = json_bytes(restore_operational(json_value(latest[parent]), plan["sources"]["personal"]["nativeOperational"]))
  native_work = dict(work)
  for key, value in latest.items():
    if key == own + "||" + IMPORTED or not key.startswith(own + "||"):
      continue
    original = plan["workMapping"].get(key)
    if original is None:
      original = key[len(own) + 2:]
      require(not original.startswith((own + "||", "profile-", "_current/", "_profile-network")), "Ambiguous new scoped state")
      require(original not in ("_machinekey", "_profiles", "_current-profile", "_daemon", "server-mode-start-key", IMPORTED), "Forbidden child authority export")
      require(not original.startswith("_serve/") or original == "_serve/b57d", "Unrelated child Serve state")
    native_work[original] = value
  # Propagate deletions instead of reviving stale credentials/runtime state.
  for combined_key, original in plan["workMapping"].items():
    if combined_key not in latest:
      native_work.pop(original, None)
  native_work[own] = json_bytes(restore_operational(json_value(latest[own]), plan["sources"]["work"]["nativeOperational"]))
  for store, label in ((native_personal, "personal"), (native_work, "work")):
    expected = plan["sources"][label]
    _, prefs, machine = selected(store, expected["binding"]["id"], expected["binding"]["node"])
    require(digest(private_key(machine)) == expected["machineHash"], "Exported machine identity changed")
    require(prefs["Config"] == json_value(latest[expected["binding"]["key"]])["Config"], "Latest credentials were not retained")
  return native_personal, native_work


def writers_stopped():
  for unit in WRITERS:
    result = subprocess.run(["/run/current-system/sw/bin/systemctl", "show", unit + ".service", "-p", "ActiveState", "--value"], capture_output=True, text=True)
    require(result.stdout.strip() in ("inactive", "failed"), "A state writer/controller is active or unknown")


def atomic_write(path, data):
  fd, name = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
  try:
    with os.fdopen(fd, "wb") as stream:
      os.fchmod(stream.fileno(), 0o600)
      stream.write(data)
      stream.flush()
      os.fsync(stream.fileno())
    os.replace(name, path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
      os.fsync(fd)
    finally:
      os.close(fd)
  finally:
    if os.path.exists(name):
      os.unlink(name)


def private_file(path):
  try:
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
      info = os.fstat(stream.fileno())
      require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and info.st_mode & 0o077 == 0 and info.st_size <= 32 * 1024 * 1024, "State file must be private and owned by the operator")
      return stream.read()
  except OSError:
    raise MigrationError("Private state file is unavailable or unsafe") from None


def private_directory(directory):
  directory.mkdir(mode=0o700, exist_ok=True)
  info = directory.stat()
  require(not directory.is_symlink() and info.st_uid == os.geteuid() and info.st_mode & 0o077 == 0, "Staging directory must be private and owned by the operator")


def prepare_import(directory, personal_path, work_path, native_personal_path, native_work_path, destination, guard=writers_stopped, write=atomic_write):
  """Persist the chosen generation/mapping before the first output write.

  Source snapshots and approved var-root mappings are caller-owned. Originals
  are never written. An existing changed combined store is never re-imported.
  """
  guard()
  private_directory(directory)
  personal = decode_store(private_file(personal_path))
  work = decode_store(private_file(work_path))
  plan_path = directory / "migration-plan.json"
  if plan_path.exists():
    plan = json_value(private_file(plan_path))
  else:
    plan = make_plan(personal, work, decode_store(private_file(native_personal_path)), decode_store(private_file(native_work_path)))
  combined = forward(personal, work, plan)
  payload = encode_store(combined)
  plan["combinedHash"] = digest(payload)
  write(plan_path, json_bytes(plan))
  guard()
  if destination.exists() or destination.is_symlink():
    require(digest(private_file(destination)) == plan["combinedHash"], "Existing combined state is not the prepared import")
  else:
    private_directory(destination.parent)
    write(destination, payload)
  return plan


def ensure_private_parents(directory):
  missing = []
  current = directory
  while not current.exists():
    require(not current.is_symlink(), "Unsafe credential directory")
    missing.append(current)
    current = current.parent
  require(current.is_dir() and not current.is_symlink() and current.stat().st_mode & 0o077 == 0, "Credential parent is not private")
  for path in reversed(missing):
    path.mkdir(mode=0o700)


def optional_file(path, private=True):
  if not path.exists() and not path.is_symlink():
    return None
  if private:
    return private_file(path)
  try:
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
      info = os.fstat(stream.fileno())
      require(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and info.st_mode & 0o022 == 0 and info.st_size <= 32 * 1024 * 1024, "Unsafe or oversized credential file")
      return stream.read()
  except OSError:
    raise MigrationError("Credential file unavailable or unsafe") from None


def file_hash(data):
  return None if data is None else digest(data)


def commit_files(directory, items, source_hash, guard=writers_stopped, write=atomic_write):
  """Stage the complete state+credential set before replacing any original.

  A completion ledger and retained staged data permit retry even if a rename
  succeeded but recording its completion failed. Callers hold the transition
  lock; all writers remain stopped until the whole set has been verified.
  """
  guard()
  private_directory(directory)
  require(len({str(row["target"]) for row in items.values()}) == len(items), "Export destinations collide")
  ledger_path = directory / "export-ledger.json"
  if ledger_path.exists():
    ledger = json_value(private_file(ledger_path))
    require(ledger["sourceHash"] == source_hash and set(ledger["files"]) == set(items), "Combined state or credential set changed during export retry")
  else:
    ledger = {"sourceHash": source_hash, "files": {}}
    for label, row in items.items():
      require(re.fullmatch(r"[a-zA-Z0-9_-]+", label) is not None, "Invalid staging label")
      payload = row["payload"]
      stage = directory / (label + ".state")
      write(stage, payload if payload is not None else b"")
      before = file_hash(optional_file(row["target"], row.get("private", True)))
      require(before == row["before"], "Native state changed since the quiesced snapshot")
      ledger["files"][label] = {"target": str(row["target"]), "before": before, "after": file_hash(payload), "done": False}
    write(ledger_path, json_bytes(ledger))
  for label, row in items.items():
    entry = ledger["files"][label]
    require(entry["target"] == str(row["target"]) and entry["after"] == file_hash(row["payload"]), "Export plan changed")
    require(digest(private_file(directory / (label + ".state"))) == digest(row["payload"] if row["payload"] is not None else b""), "Staged export changed")
  for label, row in items.items():
    guard()
    entry = ledger["files"][label]
    actual = file_hash(optional_file(row["target"], row.get("private", True)))
    require(actual in (entry["before"], entry["after"]), "Native state changed outside the export transaction")
    if actual != entry["after"]:
      if row["payload"] is None:
        row["target"].unlink()
        fd = os.open(row["target"].parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
          os.fsync(fd)
        finally:
          os.close(fd)
      else:
        ensure_private_parents(row["target"].parent)
        write(row["target"], private_file(directory / (label + ".state")))
    require(file_hash(optional_file(row["target"], row.get("private", True))) == entry["after"], "Export write verification failed")
    entry["done"] = True
    write(ledger_path, json_bytes(ledger))
  return ledger


def commit_export(directory, targets, outputs, source_hash, original_hashes, credentials=None, guard=writers_stopped, write=atomic_write):
  require(set(targets) == set(outputs) == set(original_hashes) == {"personal", "work"}, "Export requires both original stores")
  items = {label: {"target": targets[label], "payload": encode_store(outputs[label]), "before": original_hashes[label]}
           for label in ("personal", "work")}
  for path, update in (credentials or {}).items():
    label = "credential-" + digest(str(path).encode())
    require(label not in items, "Credential staging collision")
    items[label] = {"target": path, "payload": update["payload"], "before": update["before"], "private": False}
  return commit_files(directory, items, source_hash, guard, write)
