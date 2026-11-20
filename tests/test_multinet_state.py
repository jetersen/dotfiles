"""Synthetic credentials only. No production state, daemon or network access."""
import copy
import json
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "nixos/ops"))
import multinet_state as m


def key(byte):
  return "privkey:" + byte * 64


def fixture(pid, node, machine, route_all):
  own = "profile-" + pid
  profile = {"ID": pid, "Key": own, "NodeID": node, "ControlURL": m.DEFAULT_REALM}
  prefs = {
    "Config": {"NodeID": node, "PrivateNodeKey": key("3"), "OldPrivateNodeKey": key("4"),
               "NetworkLockKey": "nlpriv:" + "a" * 128, "UnknownPersistField": ["retained"]},
    "ControlURL": "", "CorpDNS": False, "OperatorUser": "joseph", "WantRunning": True,
    "RouteAll": route_all, "RunSSH": not route_all,
  }
  return {"_profiles": m.json_bytes({pid: profile}), own: m.json_bytes(prefs),
          "_machinekey": key(machine).encode(), "_current-profile": own.encode(),
          "_serve/" + pid: b'{"TCP":{"443":{"HTTPS":true}}}',
          "_daemon": b"native-daemon-only", "server-mode-start-key": own.encode(),
          "_current/user": own.encode(), "opaque-runtime": b"initial"}


class Fixture(unittest.TestCase):
  def setUp(self):
    self.p = fixture("4322", "nLsFQzqjmq11CNTRL", "1", False)
    self.w = fixture("b57d", "nYGBXVi8Wv11CNTRL", "2", True)
    self.plan = m.make_plan(self.p, self.w, work_created="2026-11-20T06:00:00.123456789Z")

  def combined(self):
    return m.forward(self.p, self.w, self.plan)


class StateTest(Fixture):
  def test_forward_distinct_machine_keys_and_originals_untouched(self):
    before = (copy.deepcopy(self.p), copy.deepcopy(self.w))
    c = self.combined()
    self.assertEqual((self.p, self.w), before)
    self.assertEqual(c["_machinekey"], self.p["_machinekey"])
    self.assertEqual(c["_current-profile"], self.p["_current-profile"])
    self.assertEqual(c["_serve/4322"], self.p["_serve/4322"])
    authority = m.json_value(c["profile-b57d||_imported-machinekey"])
    self.assertEqual(authority["MachineKey"], self.w["_machinekey"].decode())
    self.assertNotEqual(authority["MachineKey"].encode(), c["_machinekey"])
    self.assertNotIn("claims", m.json_value(c["_profile-network-4322-0"]))
    self.assertNotIn("_serve/b57d", c)
    self.assertEqual(c["profile-b57d||_serve/b57d"], self.w["_serve/b57d"])
    self.assertNotIn("profile-b57d||_daemon", c)
    self.assertNotIn("profile-b57d||_current/user", c)

  def test_personal_dns_false_true_false_and_controller_stop_baseline(self):
    native = copy.deepcopy(self.w)
    prefs = m.json_value(self.w["profile-b57d"])
    prefs["WantRunning"] = False  # native controller's down-on-stop hook
    prefs["Config"]["PrivateNodeKey"] = key("5")  # final quiesced credentials
    self.w["profile-b57d"] = m.json_bytes(prefs)
    self.plan = m.make_plan(self.p, self.w, native_work=native)
    c = self.combined()
    self.assertTrue(m.json_value(c["profile-4322"])["CorpDNS"])
    self.assertTrue(m.json_value(c["profile-b57d"])["WantRunning"])
    p, w = m.reverse(c, self.p, self.w, self.plan)
    self.assertFalse(m.json_value(p["profile-4322"])["CorpDNS"])
    self.assertFalse(m.json_value(w["profile-b57d"])["CorpDNS"])
    self.assertTrue(m.json_value(w["profile-b57d"])["WantRunning"])
    self.assertEqual(m.json_value(w["profile-b57d"])["Config"]["PrivateNodeKey"], key("5"))
    self.assertFalse(m.json_value(p["profile-4322"])["RouteAll"])

  def test_latest_rotated_node_credentials_and_complete_persist_survive_export(self):
    c = self.combined()
    for own in ("profile-4322", "profile-b57d"):
      prefs = m.json_value(c[own])
      prefs["Config"].update(PrivateNodeKey=key("6"), OldPrivateNodeKey=key("7"), NewPersistField={"future": True})
      c[own] = m.json_bytes(prefs)
    p, w = m.reverse(c, self.p, self.w, self.plan)
    for store, own in ((p, "profile-4322"), (w, "profile-b57d")):
      self.assertEqual(m.json_value(store[own])["Config"], m.json_value(c[own])["Config"])
    self.assertEqual(w["_machinekey"], self.w["_machinekey"])

  def test_new_runtime_entries_and_original_scoped_spelling(self):
    self.w["profile-b57d||existing"] = b"old"
    self.plan = m.make_plan(self.p, self.w)
    c = self.combined()
    c["profile-b57d||existing"] = b"updated"
    c["profile-b57d||new-runtime"] = b"new"
    del c["profile-b57d||opaque-runtime"]
    c["_serve/4322"] = b'{"new-personal-config":"latest"}'
    p, w = m.reverse(c, self.p, self.w, self.plan)
    self.assertEqual(w["profile-b57d||existing"], b"updated")
    self.assertNotIn("existing", w)
    self.assertEqual(w["new-runtime"], b"new")
    self.assertNotIn("opaque-runtime", w)
    self.assertEqual(p["_serve/4322"], c["_serve/4322"])
    self.assertNotIn("profile-b57d||_imported-machinekey", w)
    self.assertNotIn("profile-b57d", p)

  def test_saved_only_profiles_stay_disconnected_and_private(self):
    def add(store, pid):
      profiles = m.catalog(store)
      profiles[pid] = {"ID": pid, "Key": "profile-" + pid, "NodeID": "saved", "ControlURL": ""}
      store["_profiles"] = m.json_bytes(profiles)
      store["profile-" + pid] = b"unselected-credential-bytes"
      store["_serve/" + pid] = b"unselected-serve"
    add(self.p, "aa11")
    add(self.w, "bb22")
    self.plan = m.make_plan(self.p, self.w)
    c = self.combined()
    self.assertIn("profile-aa11", c)
    self.assertNotIn("profile-bb22", c)
    self.assertNotIn("profile-b57d||_serve/bb22", c)
    selection = m.json_value(c["_profile-network-4322-0"])
    self.assertEqual(selection, {"primary": "4322", "secondary": ["b57d"], "preferred": "4322"})
    p, w = m.reverse(c, self.p, self.w, self.plan)
    self.assertEqual(p["profile-aa11"], self.p["profile-aa11"])
    self.assertEqual(w["profile-bb22"], self.w["profile-bb22"])

  def test_precise_generation_key_and_repeatable_work_timestamp(self):
    profile = m.catalog(self.p)
    profile["4322"]["Created"] = "2026-11-20T07:00:00.123456789+01:00"
    self.p["_profiles"] = m.json_bytes(profile)
    self.plan = m.make_plan(self.p, self.w, work_created="2026-11-20T06:01:02.987654321Z")
    first = self.combined()
    second = self.combined()
    self.assertEqual(first, second)
    self.assertEqual(m.created_ns(profile["4322"]["Created"]), 1795154400123456789)
    self.assertIn("_profile-network-4322-" + format(1795154400123456789, "x"), first)
    self.assertEqual(m.catalog(first)["b57d"]["Created"], self.plan["workCreated"])

  def test_catalog_or_state_collision_rejected(self):
    self.p["profile-b57d||opaque-runtime"] = b"collision"
    self.plan = m.make_plan(self.p, self.w)
    with self.assertRaisesRegex(m.MigrationError, "collision"):
      self.combined()

  def test_same_machine_key_refused(self):
    self.w["_machinekey"] = self.p["_machinekey"]
    with self.assertRaisesRegex(m.MigrationError, "independent"):
      m.make_plan(self.p, self.w)

  def test_ambiguous_config_and_missing_selected_profile_rejected(self):
    prefs = m.json_value(self.w["profile-b57d"])
    prefs["Persist"] = copy.deepcopy(prefs["Config"])
    self.w["profile-b57d"] = m.json_bytes(prefs)
    with self.assertRaisesRegex(m.MigrationError, "ambiguous"):
      m.make_plan(self.p, self.w)
    del self.w["profile-b57d"]
    with self.assertRaisesRegex(m.MigrationError, "missing"):
      m.make_plan(self.p, self.w)

  def test_imported_binding_generation_node_realm_and_key_drift_refused(self):
    for field, value in (("Created", "2026-11-21T00:00:00Z"), ("NodeID", "replacement"),
                         ("ControlURL", "https://another-control.invalid"), ("MachineKey", key("8"))):
      with self.subTest(field=field):
        c = self.combined()
        record = m.json_value(c["profile-b57d||_imported-machinekey"])
        record[field] = value
        c["profile-b57d||_imported-machinekey"] = m.json_bytes(record)
        with self.assertRaises(m.MigrationError):
          m.reverse(c, self.p, self.w, self.plan)

  def test_reused_catalog_generation_rejected(self):
    c = self.combined()
    profiles = m.catalog(c)
    profiles["b57d"]["Created"] = "2026-11-21T00:00:00Z"
    c["_profiles"] = m.json_bytes(profiles)
    with self.assertRaisesRegex(m.MigrationError, "generation"):
      m.reverse(c, self.p, self.w, self.plan)

  def test_ambiguous_new_double_scope_and_authority_export_rejected(self):
    for name in ("profile-b57d||profile-b57d||new", "profile-b57d||_machinekey"):
      with self.subTest(name=name):
        c = self.combined()
        c[name] = b"private-bytes"
        with self.assertRaises(m.MigrationError):
          m.reverse(c, self.p, self.w, self.plan)

  def test_malformed_state_and_errors_never_include_private_values(self):
    marker = "private-secret-marker"
    for payload in (marker.encode(), m.json_bytes({"_machinekey": marker}), b'{"x":"YQ==","x":"Yg=="}'):
      with self.assertRaises(m.MigrationError) as error:
        m.decode_store(payload)
      self.assertNotIn(marker, str(error.exception))

  def test_corrupt_key_material_catalog_and_realm_rejected(self):
    for change in ("machine", "node", "old-node", "lock", "catalog", "realm"):
      with self.subTest(change=change):
        work = copy.deepcopy(self.w)
        prefs = m.json_value(work["profile-b57d"])
        if change == "machine":
          work["_machinekey"] = b"not-a-private-key"
        elif change == "catalog":
          profiles = m.catalog(work)
          profiles["b57d"]["ID"] = "reused"
          work["_profiles"] = m.json_bytes(profiles)
        elif change == "realm":
          prefs["ControlURL"] = "https://unrelated.invalid"
        else:
          field = {"node": "PrivateNodeKey", "old-node": "OldPrivateNodeKey", "lock": "NetworkLockKey"}[change]
          prefs["Config"][field] = "private-secret-marker"
        work["profile-b57d"] = m.json_bytes(prefs)
        with self.assertRaises(m.MigrationError) as error:
          m.make_plan(self.p, work)
        self.assertNotIn("private-secret-marker", str(error.exception))

  def test_missing_pre_stop_baseline_cannot_silently_fall_back(self):
    with self.assertRaisesRegex(m.MigrationError, "Missing profile catalog"):
      m.make_plan(self.p, self.w, native_work={})

  def test_corrupt_plan_cannot_replace_credentials_or_guess_old_scoping(self):
    c = self.combined()
    self.plan["sources"]["work"]["nativeOperational"]["Config"] = {"present": True, "value": {"PrivateNodeKey": key("a")}}
    with self.assertRaisesRegex(m.MigrationError, "operational override"):
      m.reverse(c, self.p, self.w, self.plan)
    del self.plan["sources"]["work"]["nativeOperational"]["Config"]
    self.plan["workMapping"] = {}
    with self.assertRaisesRegex(m.MigrationError, "mapping is missing"):
      m.reverse(c, self.p, self.w, self.plan)


class TransactionTest(Fixture):
  def setUp(self):
    super().setUp()
    self.tmp = tempfile.TemporaryDirectory()
    self.addCleanup(self.tmp.cleanup)
    self.root = Path(self.tmp.name)
    self.paths = {k: self.root / (k + ".state") for k in ("personal", "work")}
    for name, store in (("personal", self.p), ("work", self.w)):
      m.atomic_write(self.paths[name], m.encode_store(store))
    self.originals = {k: v.read_bytes() for k, v in self.paths.items()}
    self.hashes = {k: m.digest(v) for k, v in self.originals.items()}

  def export(self, write=m.atomic_write, guard=lambda: None):
    c = self.combined()
    prefs = m.json_value(c["profile-b57d"])
    prefs["Config"]["PrivateNodeKey"] = key("9")
    c["profile-b57d"] = m.json_bytes(prefs)
    p, w = m.reverse(c, self.p, self.w, self.plan)
    return m.commit_export(self.root / "export", self.paths, {"personal": p, "work": w}, m.digest(m.encode_store(c)), self.hashes, guard=guard, write=write)

  def test_both_outputs_staged_before_either_original_write(self):
    def write(path, data):
      if path in self.paths.values():
        self.assertTrue((self.root / "export/personal.state").exists())
        self.assertTrue((self.root / "export/work.state").exists())
      m.atomic_write(path, data)
    ledger = self.export(write=write)
    self.assertTrue(all(v["done"] for v in ledger["files"].values()))

  def test_partial_reverse_export_retry_retains_latest_keys(self):
    def write(path, data):
      if path == self.paths["work"]:
        raise OSError("synthetic write fault")
      m.atomic_write(path, data)
    with self.assertRaises(OSError):
      self.export(write=write)
    self.assertEqual(self.paths["work"].read_bytes(), self.originals["work"])
    ledger = self.export()
    self.assertTrue(all(v["done"] for v in ledger["files"].values()))
    work = m.decode_store(self.paths["work"].read_bytes())
    self.assertEqual(m.json_value(work["profile-b57d"])["Config"]["PrivateNodeKey"], key("9"))

  def test_ledger_fault_after_file_replace_is_resumable(self):
    writes = 0
    def write(path, data):
      nonlocal writes
      if path.name == "export-ledger.json":
        writes += 1
        if writes == 2:
          raise OSError("ledger fault after personal replacement")
      m.atomic_write(path, data)
    with self.assertRaises(OSError):
      self.export(write=write)
    self.assertTrue(all(v["done"] for v in self.export()["files"].values()))

  def test_active_writer_refuses_all_writes(self):
    def guard():
      raise m.MigrationError("writer active")
    with self.assertRaisesRegex(m.MigrationError, "writer active"):
      self.export(guard=guard)
    self.assertFalse((self.root / "export").exists())
    self.assertEqual({k: p.read_bytes() for k, p in self.paths.items()}, self.originals)

  def test_forward_output_fault_reuses_persisted_generation(self):
    destination = self.root / "combined/state"
    def write(path, data):
      if path == destination:
        raise OSError("prefs output fault")
      m.atomic_write(path, data)
    args = (self.root / "import", self.paths["personal"], self.paths["work"], self.paths["personal"], self.paths["work"], destination)
    with self.assertRaises(OSError):
      m.prepare_import(*args, guard=lambda: None, write=write)
    before = json.loads((self.root / "import/migration-plan.json").read_text())
    after = m.prepare_import(*args, guard=lambda: None)
    self.assertEqual(before["workCreated"], after["workCreated"])
    self.assertEqual(after, m.prepare_import(*args, guard=lambda: None))
    self.assertEqual({k: p.read_bytes() for k, p in self.paths.items()}, self.originals)

  def test_import_never_overwrites_new_runtime_state(self):
    args = (self.root / "import", self.paths["personal"], self.paths["work"], self.paths["personal"], self.paths["work"], self.root / "combined/state")
    m.prepare_import(*args, guard=lambda: None)
    m.atomic_write(args[-1], b"new runtime state")
    with self.assertRaisesRegex(m.MigrationError, "not the prepared import"):
      m.prepare_import(*args, guard=lambda: None)
    self.assertEqual(args[-1].read_bytes(), b"new runtime state")

  def test_default_guard_detects_active_daemon_and_controller(self):
    args = (self.root / "import", self.paths["personal"], self.paths["work"], self.paths["personal"], self.paths["work"], self.root / "combined/state")
    for values in (("active",), ("inactive", "inactive", "active"), ("inactive", "inactive", "inactive", "active"), ("",)):
      with self.subTest(values=values), mock.patch.object(m.subprocess, "run", side_effect=[SimpleNamespace(stdout=v) for v in values]):
        with self.assertRaisesRegex(m.MigrationError, "active or unknown"):
          m.prepare_import(*args)
        self.assertFalse(args[0].exists())

  def test_public_or_symlink_state_source_is_refused(self):
    args = (self.root / "import", self.paths["personal"], self.paths["work"], self.paths["personal"], self.paths["work"], self.root / "combined/state")
    self.paths["personal"].chmod(0o644)
    with self.assertRaisesRegex(m.MigrationError, "private"):
      m.prepare_import(*args, guard=lambda: None)
    self.paths["personal"].unlink()
    self.paths["personal"].symlink_to(self.paths["work"])
    with self.assertRaisesRegex(m.MigrationError, "unsafe"):
      m.prepare_import(*args, guard=lambda: None)

  def test_changed_latest_source_cannot_resume_an_old_partial_export(self):
    def fail_work(path, data):
      if path == self.paths["work"]:
        raise OSError("interrupted")
      m.atomic_write(path, data)
    with self.assertRaises(OSError):
      self.export(write=fail_work)
    after_fault = {k: path.read_bytes() for k, path in self.paths.items()}
    c = self.combined()
    p, w = m.reverse(c, self.p, self.w, self.plan)
    with self.assertRaisesRegex(m.MigrationError, "changed during export retry"):
      m.commit_export(self.root / "export", self.paths, {"personal": p, "work": w}, "different-latest-source", self.hashes, guard=lambda: None)
    self.assertEqual({k: path.read_bytes() for k, path in self.paths.items()}, after_fault)


if __name__ == "__main__":
  unittest.main()
