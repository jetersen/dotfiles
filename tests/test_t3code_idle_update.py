import argparse
from contextlib import closing
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('idle_update', ROOT / 'nixos/hosts/rocket/t3code-idle-update.py')
idle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(idle)


class IdleUpdateTests(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.root = Path(self.temp.name)
    self.database = self.root / 'statev2.sqlite'
    with closing(sqlite3.connect(self.database)) as db, db:
      for name in idle.TERMINAL:
        db.execute(f'CREATE TABLE orchestration_v2_projection_{name} (status TEXT, payload_json TEXT)')
      db.execute('CREATE TABLE orchestration_v2_effect_outbox (status TEXT)')
      db.execute('CREATE TABLE orchestration_v2_events (sequence INTEGER PRIMARY KEY)')
      db.execute('INSERT INTO orchestration_v2_events VALUES (7)')

  def insert(self, table, status, payload='{}'):
    with closing(sqlite3.connect(self.database)) as db, db:
      if table == 'effect_outbox':
        db.execute('INSERT INTO orchestration_v2_effect_outbox VALUES (?)', (status,))
      else:
        db.execute(f'INSERT INTO orchestration_v2_projection_{table} VALUES (?, ?)', (status, payload))

  def test_empty_and_terminal_history_are_idle(self):
    self.assertEqual(idle.idle_snapshot(self.database), 7)
    for table, statuses in idle.TERMINAL.items():
      for status in statuses:
        self.insert(table, status)
    self.insert('effect_outbox', 'succeeded')
    self.assertEqual(idle.idle_snapshot(self.database), 7)

  def test_each_kind_of_pending_work_blocks_updates(self):
    for table, status in [('runs', s) for s in ('preparing', 'queued', 'starting', 'running', 'waiting')] + [
        ('run_attempts', 'pending'), ('provider_turns', 'running'),
        ('subagents', 'running'), ('runtime_requests', 'pending'),
        ('provider_sessions', 'starting'), ('provider_threads', 'active'),
        ('effect_outbox', 'pending')]:
      with self.subTest(table=table, status=status):
        self.insert(table, status)
        self.assertIsNone(idle.idle_snapshot(self.database))
        with closing(sqlite3.connect(self.database)) as db, db:
          name = 'orchestration_v2_effect_outbox' if table == 'effect_outbox' else f'orchestration_v2_projection_{table}'
          db.execute(f'DELETE FROM {name}')

  def test_unknown_status_blocks_updates(self):
    self.insert('runs', 'future-status')
    self.assertIsNone(idle.idle_snapshot(self.database))

  def test_background_work_outliving_turn_blocks_updates(self):
    self.insert('provider_threads', 'idle', json.dumps({'pendingBackgroundTasks': [{'id': 'task'}]}))
    self.assertIsNone(idle.idle_snapshot(self.database))

  def test_missing_database_is_not_created(self):
    absent = self.root / 'absent.sqlite'
    with self.assertRaises(sqlite3.OperationalError):
      idle.idle_snapshot(absent)
    self.assertFalse(absent.exists())

  def test_unknown_schema_blocks_updates(self):
    with closing(sqlite3.connect(self.database)) as db, db:
      db.execute('DROP TABLE orchestration_v2_projection_subagents')
    with self.assertRaises(sqlite3.OperationalError):
      idle.idle_snapshot(self.database)

  def test_new_activity_or_package_resets_quiet_period(self):
    state, ready = idle.quiet_long_enough({}, ['pid', 'old', 'new'], 7, 100, 120)
    self.assertFalse(ready)
    self.assertFalse(idle.quiet_long_enough(state, ['pid', 'old', 'new'], 7, 219, 120)[1])
    self.assertTrue(idle.quiet_long_enough(state, ['pid', 'old', 'new'], 7, 220, 120)[1])
    self.assertFalse(idle.quiet_long_enough(state, ['pid', 'old', 'new'], 8, 220, 120)[1])
    self.assertFalse(idle.quiet_long_enough(state, ['pid', 'old', 'newer'], 7, 220, 120)[1])

  def args(self):
    package = self.root / 'package'
    package.joinpath('bin').mkdir(parents=True)
    package.joinpath('bin/t3').touch()
    return argparse.Namespace(package=package, database=self.database, state=self.root / 'idle.json',
                              systemctl='systemctl', quiet_seconds=0, check=False)

  def test_restart_requires_quiet_period_and_final_idle_recheck(self):
    args = self.args()
    with patch.object(idle, 'service_pid', return_value=os.getpid()), \
         patch.object(idle, 'owns_database', return_value=True), \
         patch.object(idle, 'stop_if_still_idle', return_value=True) as restart:
      self.assertIn('quiet period', idle.update(args))
      restart.assert_not_called()
      with patch.object(idle, 'idle_snapshot', side_effect=[7, None]):
        self.assertIn('new activity', idle.update(args))
      restart.assert_not_called()
      idle.update(args)
      self.assertIn('applied staged', idle.update(args))
      restart.assert_called_once_with(args.database, os.getpid(), 7)

  def test_busy_server_never_restarts(self):
    args = self.args()
    self.insert('runs', 'running')
    with patch.object(idle, 'service_pid', return_value=os.getpid()), \
         patch.object(idle, 'owns_database', return_value=True), \
         patch.object(idle, 'stop_if_still_idle') as restart:
      self.assertIn('update deferred', idle.update(args))
      restart.assert_not_called()
      self.assertFalse(args.state.exists())

  def fake_server(self):
    process = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
    self.addCleanup(lambda: (process.kill(), process.wait()) if process.poll() is None else None)
    return process

  def test_atomic_check_stops_only_idle_fixture_process(self):
    process = self.fake_server()
    before = self.database.read_bytes()
    self.assertTrue(idle.stop_if_still_idle(self.database, process.pid, 7))
    self.assertEqual(process.wait(timeout=3), -9)
    self.assertEqual(self.database.read_bytes(), before)

  def test_work_arriving_before_suspend_resumes_fixture_process(self):
    process = self.fake_server()
    self.insert('runs', 'running')
    self.assertFalse(idle.stop_if_still_idle(self.database, process.pid, 7))
    self.assertIsNone(process.poll())
    self.assertNotIn('\nState:\tT ', Path(f'/proc/{process.pid}/status').read_text())

  def test_writer_reservation_excludes_uncommitted_work(self):
    process = self.fake_server()
    with closing(sqlite3.connect(self.database, timeout=0)) as other:
      other.execute('BEGIN IMMEDIATE')
      other.execute("INSERT INTO orchestration_v2_projection_runs VALUES ('running','{}')")
      with self.assertRaises(sqlite3.OperationalError):
        idle.stop_if_still_idle(self.database, process.pid, 7)
      self.assertIsNone(process.poll())


if __name__ == '__main__':
  unittest.main()
