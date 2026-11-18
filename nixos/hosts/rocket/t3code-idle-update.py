"""Apply a staged T3 package only after the running server becomes idle."""

import argparse
from contextlib import closing
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import time


# Verified against T3 0.1.9's orchestration V2 schema. Unknown statuses block
# updates too. An idle provider session may stay open between turns.
TERMINAL = {
  'runs': ('completed', 'interrupted', 'failed', 'cancelled', 'rolled_back'),
  'run_attempts': ('completed', 'interrupted', 'failed', 'cancelled', 'superseded'),
  'provider_turns': ('completed', 'interrupted', 'failed', 'cancelled'),
  'subagents': ('idle', 'completed', 'failed', 'cancelled', 'interrupted'),
  'runtime_requests': ('resolved', 'expired', 'cancelled'),
  'provider_sessions': ('ready', 'stopped', 'error'),
  'provider_threads': ('not_loaded', 'idle', 'archived', 'closed', 'error'),
}


def idle_snapshot(database):
  """Return an activity revision if idle, otherwise None. Never write T3's DB."""
  deadline = time.monotonic() + 2
  with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=ro', uri=True, timeout=1)) as db:
    db.set_progress_handler(lambda: time.monotonic() > deadline, 1000)
    db.execute('BEGIN')
    return idle_revision(db)


def idle_revision(db):
  for suffix, terminal in TERMINAL.items():
    placeholders = ','.join('?' for _ in terminal)
    if db.execute(
        f'SELECT 1 FROM orchestration_v2_projection_{suffix} '
        f'WHERE status IS NULL OR status NOT IN ({placeholders}) LIMIT 1', terminal).fetchone():
      return None
  if db.execute(
      "SELECT 1 FROM orchestration_v2_effect_outbox "
      "WHERE status IS NULL OR status NOT IN ('succeeded','failed','cancelled') LIMIT 1").fetchone():
    return None
  # Delegated/background work can outlive its parent's turn.
  if db.execute(
      "SELECT 1 FROM orchestration_v2_projection_provider_threads "
      "WHERE json_array_length(json_extract(payload_json, '$.pendingBackgroundTasks')) > 0 LIMIT 1"
  ).fetchone():
    return None
  return db.execute('SELECT COALESCE(MAX(sequence), 0) FROM orchestration_v2_events').fetchone()[0]


def stop_if_still_idle(database, pid, revision):
  """Reserve SQLite's writer, suspend the server, then verify and stop it.

  The writer reservation ensures no uncommitted turn can be hidden by SQLite's
  snapshot isolation. SIGSTOP prevents new work between the final check and
  stopping the process. No T3 records are modified. Restart=always starts the
  staged executable after the stopped, idle process exits.
  """
  with closing(sqlite3.connect(database.resolve().as_uri() + '?mode=rw', uri=True, timeout=1)) as db:
    deadline = time.monotonic() + 2
    db.set_progress_handler(lambda: time.monotonic() > deadline, 1000)
    db.execute('BEGIN IMMEDIATE')
    with closing(os.fdopen(os.pidfd_open(pid), 'rb')) as process:
      suspended = False
      try:
        signal.pidfd_send_signal(process.fileno(), signal.SIGSTOP)
        suspended = True
        # Signal delivery is asynchronous; wait until all server threads stop.
        while '\nState:\tT ' not in Path(f'/proc/{pid}/status').read_text():
          if time.monotonic() >= deadline:
            raise RuntimeError('Server did not suspend')
          time.sleep(0.01)
        if idle_revision(db) != revision:
          return False
        # A graceful stop would resume the event loop and reopen the race.
        # Only an idle server reaches here; systemd cleans up its idle providers.
        signal.pidfd_send_signal(process.fileno(), signal.SIGKILL)
        suspended = False
        return True
      finally:
        if suspended:
          signal.pidfd_send_signal(process.fileno(), signal.SIGCONT)


def quiet_long_enough(state, identity, revision, now, seconds):
  if state.get('identity') != identity or state.get('revision') != revision:
    return {'identity': identity, 'revision': revision, 'since': now}, False
  return state, now - state['since'] >= seconds


def service_pid(systemctl):
  return int(subprocess.check_output(
    [systemctl, '--user', 'show', 't3code.service', '--property=MainPID', '--value'], text=True).strip())


def owns_database(pid, database):
  expected = database.stat()
  for fd in Path(f'/proc/{pid}/fd').iterdir():
    try:
      actual = fd.stat()
      if (actual.st_dev, actual.st_ino) == (expected.st_dev, expected.st_ino):
        return True
    except FileNotFoundError:
      continue
  return False


def update(args):
  pid = service_pid(args.systemctl)
  if not pid:
    return 'server stopped; nothing to update'
  running = Path(f'/proc/{pid}/exe').resolve(strict=True)
  # bin/t3 is a wrapper in the CLI derivation; its ELF is under lib/t3/t3.
  desired = args.package.joinpath('bin/t3').resolve(strict=True).parent.parent / 'lib/t3/t3'
  if running == desired:
    args.state.unlink(missing_ok=True)
    return 'server package is current'
  if not owns_database(pid, args.database):
    raise RuntimeError('Server does not own the configured database')
  revision = idle_snapshot(args.database)
  if revision is None:
    args.state.unlink(missing_ok=True)
    return 'agents or pending work; update deferred'
  if args.check:
    return 'idle now; check mode does not restart the server'
  identity = [pid, str(running), str(desired)]
  state = json.loads(args.state.read_text()) if args.state.exists() else {}
  state, ready = quiet_long_enough(state, identity, revision, time.monotonic(), args.quiet_seconds)
  args.state.write_text(json.dumps(state) + '\n')
  if not ready:
    return 'waiting for a continuous quiet period'
  # Recheck after the quiet period, including PID and activity revision. A new
  # turn, approval or delegated task resets the wait instead of being interrupted.
  if service_pid(args.systemctl) != pid or idle_snapshot(args.database) != revision:
    args.state.unlink(missing_ok=True)
    return 'new activity; update deferred'
  if not stop_if_still_idle(args.database, pid, revision):
    args.state.unlink(missing_ok=True)
    return 'new activity; update deferred'
  args.state.unlink(missing_ok=True)
  return 'applied staged server update while idle'


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--package', type=Path, required=True)
  parser.add_argument('--database', type=Path, required=True)
  parser.add_argument('--state', type=Path, required=True)
  parser.add_argument('--systemctl', required=True)
  parser.add_argument('--quiet-seconds', type=int, default=120)
  parser.add_argument('--check', action='store_true')
  args = parser.parse_args()
  try:
    print(update(args))
  except (OSError, ValueError, sqlite3.Error, subprocess.SubprocessError, RuntimeError) as error:
    args.state.unlink(missing_ok=True)
    print(f'Cannot establish idle state; update deferred: {type(error).__name__}')
    raise SystemExit(1)


if __name__ == '__main__':
  main()
