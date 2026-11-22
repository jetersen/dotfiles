"""Verify snapshots are self-contained and preserve the source."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "nixos/hosts/rocket/agent-observability"))

import hashlib
import json
import sqlite3
import tempfile
import unittest
from contextlib import closing

from agent_backup import snapshot_database, write_snapshot_manifest


class SnapshotTests(unittest.TestCase):
    def test_wal_database_restores_without_sidecars(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root / "source.sqlite", root / "snapshot.sqlite"
            with closing(sqlite3.connect(source)) as writer:
                writer.execute("PRAGMA journal_mode=WAL")
                writer.execute("CREATE TABLE messages(text TEXT)")
                writer.execute("INSERT INTO messages VALUES ('retained conversation')")
                writer.commit()
                snapshot_database(source, target)
                self.assertEqual(writer.execute("SELECT count(*) FROM messages").fetchone(), (1,))
            with closing(sqlite3.connect(target)) as restored:
                self.assertEqual(restored.execute("PRAGMA integrity_check").fetchone(), ("ok",))
                self.assertEqual(
                    restored.execute("SELECT text FROM messages").fetchone(),
                    ("retained conversation",),
                )
            self.assertFalse(Path(str(target) + "-wal").exists())
            self.assertFalse(target.with_suffix(".partial").exists())

    def test_manifest_can_validate_recovered_database_independently(self):
        with tempfile.TemporaryDirectory() as directory:
            database = Path(directory) / "statev2.sqlite"
            tables = [
                "projection_projects",
                "orchestration_v2_projection_threads",
                "orchestration_v2_projection_messages",
            ]
            with closing(sqlite3.connect(database)) as db:
                for table in tables:
                    db.execute("CREATE TABLE " + table + " (id INTEGER)")
                    db.execute("INSERT INTO " + table + " VALUES (1)")
                db.commit()
            write_snapshot_manifest(database)
            manifest = json.loads((database.parent / "snapshot-manifest.json").read_text())
            self.assertEqual(manifest["database"], database.name)
            self.assertEqual(manifest["sha256"], hashlib.sha256(database.read_bytes()).hexdigest())
            self.assertEqual(manifest["counts"], {table: 1 for table in tables})


if __name__ == "__main__":
    unittest.main()
