"""Version-sensitive T3 credential resolver. Stdout is secret; capture via a pipe."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import resource
import sqlite3
import sys
import urllib.parse

from poll import endpoint_url, loopback_url, SIGNATURE


def runtime_identity(pid):
  if type(pid) is not int or pid <= 0:
    raise ValueError('Invalid runtime PID')
  # comm can contain spaces and parentheses; the last ')' ends that field.
  stat = (Path('/proc') / str(pid) / 'stat').read_text().rpartition(')')[2].split()
  return {'bootId': Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
          'startTicks': int(stat[19])}


def resolve(c):
  compat = c['t3Compatibility']
  origin = compat['origin']
  parsed = urllib.parse.urlsplit(loopback_url(origin + '/'))
  if parsed.path != '/' or origin.endswith('/'):
    raise ValueError('Bare loopback origin required')
  pid = compat['runtimePid']
  identity = runtime_identity(pid)
  if identity != compat['runtimeIdentity']:
    raise ValueError('Runtime restarted; rediscover compatibility')
  # Inspect the exact bundle before pinning its hash, boot ID and start time.
  with (Path('/proc') / str(pid) / 'exe').open('rb') as stream:
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
