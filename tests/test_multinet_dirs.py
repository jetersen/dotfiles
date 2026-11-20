"""Synthetic SSH/certificate/profile data; no production credentials."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "nixos/ops"))
import multinet_state as state
import multinet_dirs as dirs


class DirectoryTest(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.TemporaryDirectory()
    self.addCleanup(self.tmp.cleanup)
    self.root = Path(self.tmp.name)
    self.personal = self.root / "personal"
    self.work = self.root / "work"
    self.combined = self.root / "combined"
    for path in (self.personal, self.work, self.combined):
      path.mkdir(mode=0o700)
    self.prefixes = {"certs": "personal", "ssh": "personal", "profile-data/4322": "personal",
                     "profile-data/b57d": "work", "files/personal-uid-1": "personal", "files/work-uid-2": "work"}
    self.put(self.personal / "certs/node.key", b"synthetic-personal-TLS-key")
    self.put(self.personal / "ssh/host.key", b"synthetic-personal-SSH-key")
    self.put(self.personal / "profile-data/4322/credentials", b"personal-data")
    self.put(self.work / "profile-data/b57d/credentials", b"work-data")

  def put(self, path, value):
    state.ensure_private_parents(path.parent)
    state.atomic_write(path, value)

  def prepare(self):
    baseline = {}
    for owner, root in (("personal", self.personal), ("work", self.work)):
      baseline.update(dirs.inventory(root, self.prefixes, owner))
    updates = dirs.forward_updates(self.personal, self.work, self.combined, self.prefixes)
    dirs.install_forward(updates, guard=lambda: None)
    return baseline

  def test_personal_ssh_certs_and_both_profile_directories_retained(self):
    baseline = self.prepare()
    self.assertEqual((self.combined / "certs/node.key").read_bytes(), b"synthetic-personal-TLS-key")
    self.assertEqual((self.combined / "ssh/host.key").read_bytes(), b"synthetic-personal-SSH-key")
    self.assertEqual((self.combined / "profile-data/b57d/credentials").read_bytes(), b"work-data")
    self.assertEqual(baseline["profile-data/b57d/credentials"]["owner"], "work")

  def test_new_runtime_work_data_and_rotated_tls_export_to_correct_owner(self):
    baseline = self.prepare()
    self.put(self.combined / "profile-data/b57d/new-runtime-key", b"new-work-key")
    self.put(self.combined / "certs/node.key", b"renewed-personal-TLS-key")
    self.put(self.combined / "multi-profile-host-identities.json", b"private-experimental-slots")
    updates = dirs.reverse_updates(self.combined, {"personal": self.personal, "work": self.work}, baseline, self.prefixes)
    self.assertEqual(updates[self.work / "profile-data/b57d/new-runtime-key"], {"payload": b"new-work-key", "before": None})
    self.assertEqual(updates[self.personal / "certs/node.key"]["payload"], b"renewed-personal-TLS-key")
    self.assertNotIn(self.personal / "multi-profile-host-identities.json", updates)

  def test_unknown_credential_directory_stops_before_copy(self):
    self.put(self.work / "unmapped-credential/key", b"private-dependency")
    with self.assertRaisesRegex(state.MigrationError, "Unmapped"):
      dirs.forward_updates(self.personal, self.work, self.combined, self.prefixes)
    self.assertEqual(list(self.combined.iterdir()), [])

  def test_wrong_owner_and_symlink_rejected(self):
    self.put(self.work / "certs/node.key", b"not-personal")
    with self.assertRaisesRegex(state.MigrationError, "ownership"):
      dirs.forward_updates(self.personal, self.work, self.combined, self.prefixes)
    (self.work / "certs/node.key").unlink()
    (self.work / "certs").rmdir()
    (self.work / "profile-data/b57d/link").symlink_to(self.personal / "certs/node.key")
    with self.assertRaisesRegex(state.MigrationError, "Symlink"):
      dirs.forward_updates(self.personal, self.work, self.combined, self.prefixes)

  def test_existing_runtime_credentials_never_replaced_by_initial_copy(self):
    self.prepare()
    self.put(self.combined / "certs/node.key", b"newer-key")
    updates = dirs.forward_updates(self.personal, self.work, self.combined, self.prefixes)
    with self.assertRaisesRegex(state.MigrationError, "already different"):
      dirs.install_forward(updates, guard=lambda: None)
    self.assertEqual((self.combined / "certs/node.key").read_bytes(), b"newer-key")

  def test_removed_runtime_credentials_are_not_revived(self):
    baseline = self.prepare()
    (self.combined / "ssh/host.key").unlink()
    updates = dirs.reverse_updates(self.combined, {"personal": self.personal, "work": self.work}, baseline, self.prefixes)
    self.assertIsNone(updates[self.personal / "ssh/host.key"]["payload"])

  def test_credential_fault_after_state_export_retries_as_one_transaction(self):
    baseline = self.prepare()
    self.put(self.combined / "certs/node.key", b"latest-cert-key")
    self.put(self.combined / "profile-data/b57d/new", b"latest-work-data")
    updates = dirs.reverse_updates(self.combined, {"personal": self.personal, "work": self.work}, baseline, self.prefixes)
    personal_state, work_state = self.personal / "tailscaled.state", self.work / "tailscaled.state"
    self.put(personal_state, b"old-personal-state")
    self.put(work_state, b"old-work-state")
    items = {"personal": {"target": personal_state, "payload": b"latest-personal-state", "before": state.digest(b"old-personal-state")},
             "work": {"target": work_state, "payload": b"latest-work-state", "before": state.digest(b"old-work-state")}}
    for n, (target, row) in enumerate(updates.items()):
      items["credential-" + str(n)] = {"target": target, "payload": row["payload"], "before": row["before"], "private": False}
    def fail_cert(path, value):
      if path in {row["target"] for row in items.values()}:
        self.assertTrue(all((self.root / "export" / (name + ".state")).is_file() for name in items))
      if path == self.personal / "certs/node.key":
        raise OSError("synthetic certificate write fault")
      state.atomic_write(path, value)
    with self.assertRaises(OSError):
      state.commit_files(self.root / "export", items, "latest-state-and-tree", guard=lambda: None, write=fail_cert)
    self.assertEqual(personal_state.read_bytes(), b"latest-personal-state")
    ledger = state.commit_files(self.root / "export", items, "latest-state-and-tree", guard=lambda: None)
    self.assertTrue(all(v["done"] for v in ledger["files"].values()))
    self.assertEqual((self.personal / "certs/node.key").read_bytes(), b"latest-cert-key")
    self.assertEqual((self.work / "profile-data/b57d/new").read_bytes(), b"latest-work-data")


if __name__ == "__main__":
  unittest.main()
