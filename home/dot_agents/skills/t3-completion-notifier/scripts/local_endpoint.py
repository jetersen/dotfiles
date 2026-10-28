"""Version-sensitive T3 credential resolver. Stdout is secret; capture via a pipe."""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import socket
import sqlite3
import sys
import urllib.parse

from poll import command, endpoint_url, loopback_url, SIGNATURE


def runtime_identity(pid):
  if type(pid) is not int or pid <= 0:
    raise ValueError('Invalid runtime PID')
  # comm can contain spaces and parentheses; the last ')' ends that field.
  stat = (Path('/proc') / str(pid) / 'stat').read_text().rpartition(')')[2].split()
  return {'bootId': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
          'startTicks': int(stat[19])}


def runtime_state(c):
  compat = c['t3Compatibility']
  if 'runtimeUnit' not in compat:
    pid = compat['runtimePid']
    identity = runtime_identity(pid)
    if identity != compat['runtimeIdentity']:
      raise ValueError('Runtime restarted; rediscover compatibility')
    return pid, identity
  name = compat['runtimeUnit']
  if (not isinstance(name, str) or len(name) > 255 or
      not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_:@.-]*\.service', name) or
      'runtimePid' in compat or 'runtimeIdentity' in compat or
      not Path(c['systemctl']).is_absolute()):
    raise ValueError('One explicit user service required')
  raw = command([c['systemctl'], '--user', 'show', name,
                 '--property=LoadState,ActiveState,MainPID'], 2, 4096)
  fields = dict(line.split('=', 1) for line in raw.decode().splitlines() if '=' in line)
  pid = int(fields['MainPID'])
  if (fields.get('LoadState') != 'loaded' or fields.get('ActiveState') != 'active' or
      pid <= 0 or
      Path('/proc', str(pid)).stat().st_uid != os.getuid()):
    raise ValueError('Expected user service unavailable')
  return pid, runtime_identity(pid)


def verify_binding(pid, origin, database):
  """Verify the declared local listener and SQLite inode before releasing credentials."""
  expected_db = database.stat()
  owns_db, sockets = False, set()
  for fd in Path('/proc', str(pid), 'fd').iterdir():
    try:
      target = os.readlink(fd)
      if target.startswith('socket:['):
        sockets.add(target[8:-1])
      stat = fd.stat()
      owns_db |= (stat.st_dev, stat.st_ino) == (expected_db.st_dev, expected_db.st_ino)
    except FileNotFoundError:
      continue  # An unrelated descriptor can close during the snapshot.
  if not owns_db:
    raise ValueError('Runtime does not own configured database')
  ipv4 = origin.hostname == '127.0.0.1'
  address = socket.inet_pton(socket.AF_INET if ipv4 else socket.AF_INET6, origin.hostname)
  address = b''.join(address[i:i + 4][::-1] for i in range(0, len(address), 4)).hex().upper()
  table = Path('/proc', str(pid), 'net', 'tcp' if ipv4 else 'tcp6').read_text()
  for line in table.splitlines()[1:]:
    fields = line.split()
    host, port = fields[1].split(':')
    if (fields[3] == '0A' and fields[9] in sockets and int(port, 16) == origin.port and
        host in {address, '0' * len(address)}):
      return
  raise ValueError('Runtime does not own configured loopback listener')


def resolve(c):
  compat = c['t3Compatibility']
  origin = compat['origin']
  parsed = urllib.parse.urlsplit(loopback_url(origin + '/'))
  if parsed.path != '/' or origin.endswith('/'):
    raise ValueError('Bare loopback origin required')
  pid, identity = runtime_state(c)
  # Inspect the exact bundle before pinning its hash, boot ID and start time.
  with (Path('/proc') / str(pid) / 'exe').open('rb') as stream:
    executable = os.fstat(stream.fileno())
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
  if digest != compat['runtimeSha256'] or runtime_identity(pid) != identity:
    raise ValueError('Runtime changed; inspect compatibility again')
  for artifact in compat.get('runtimeArtifacts', []):
    path = Path(artifact['path'])
    if not path.is_absolute():
      raise ValueError('Absolute runtime artifact required')
    with path.open('rb') as stream:
      if hashlib.file_digest(stream, 'sha256').hexdigest() != artifact['sha256']:
        raise ValueError('Loaded runtime artifact changed')
  if runtime_identity(pid) != identity:
    raise ValueError('Runtime changed while checking artifacts')
  db = Path(compat['database'])
  if not db.is_absolute():
    raise ValueError('Absolute database required')
  if 'runtimeUnit' in compat:
    verify_binding(pid, parsed, db)
  # Read only this exact new task's credentials; never enumerate app secrets.
  with closing(sqlite3.connect(db.as_uri() + '?mode=ro', uri=True, timeout=2)) as connection:
    row = connection.execute(
      'SELECT webhook_token, webhook_secret, enabled, project_id, thread_id, schedule_json '
      'FROM scheduled_tasks WHERE task_id = ?', (c['scheduledTaskId'],)).fetchone()
  if not row or row[2] != 1 or row[3] != c['projectId'] or row[4] != c['threadId']:
    raise ValueError('Schedule unavailable or binding mismatch')
  token, key, _, _, _, schedule_json = row
  schedule = json.loads(schedule_json)
  filters = schedule.get('filters', [])
  dedupe = schedule.get('dedupe') or {}
  required_filters = [{'path': 'body.' + k, 'op': 'equals', 'value': c[k]}
                      for k in ('watchId', 'jobId')]
  required_filters.append({'path': 'body.event', 'op': 'equals', 'value': 'job_terminal'})
  if (schedule.get('type') != 'webhook' or schedule.get('signature') != SIGNATURE or
      dedupe.get('replayKey') != '{{body.eventId}}' or
      any(dedupe.get(k) is not None for k in ('coalesceKey', 'coalesceWindowSeconds')) or
      any(f not in filters for f in required_filters)):
    raise ValueError('Webhook contract mismatch')
  if (not isinstance(token, str) or not token or len(token) > 512 or
      not isinstance(key, str) or not 32 <= len(key.encode()) <= 4096):
    raise ValueError('Missing or invalid credentials')
  if runtime_state(c) != (pid, identity):
    raise ValueError('Runtime changed during credential resolution')
  current_exe = Path('/proc', str(pid), 'exe').stat()
  if (current_exe.st_dev, current_exe.st_ino) != (executable.st_dev, executable.st_ino):
    raise ValueError('Runtime executable changed')
  if 'runtimeUnit' in compat:
    verify_binding(pid, parsed, db)
  delivery_origin = c.get('httpsOrigin', origin)
  url = delivery_origin + '/api/hooks/' + urllib.parse.quote(c['scheduledTaskId'], safe='') + '/' + urllib.parse.quote(token, safe='')
  return {'url': endpoint_url(c, url), 'signingKey': key}


def main():
  resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('--config', required=True)
  args = parser.parse_args()
  try:
    credentials = resolve(json.loads(Path(args.config).read_text()))
  except Exception as error:
    print(type(error).__name__, file=sys.stderr)
    return 1
  print(json.dumps(credentials))
  return 0


if __name__ == '__main__':
  raise SystemExit(main())
