"""Run a job with a durable completion record, or read that record as a status adapter."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

from poll import atomic, command, now


def identity(c):
  commands = [c['jobCommand'], c['resultCommand']]
  for argv in commands:
    if (not isinstance(argv, list) or not argv or not Path(argv[0]).is_absolute() or
        any(not isinstance(arg, str) or not arg for arg in argv)):
      raise ValueError('Absolute job and result commands required')
  return {'jobId': c['jobId'], 'watchId': c['watchId'],
          'commandsSha256': hashlib.sha256(json.dumps(commands).encode()).hexdigest()}


def run(c):
  expected = identity(c)
  path = Path(c['jobRecord'])
  if (not path.is_absolute() or path.parent.is_symlink() or
      path.parent.stat().st_uid != os.getuid() or path.parent.stat().st_mode & 0o077):
    raise ValueError('Private job record directory required')
  with path.with_name(path.name + '.lock').open('a') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    if path.exists():
      raise ValueError('Job record already exists')
    record = {'identity': expected, 'phase': 'running', 'startedAtUtc': now(),
              'invocationId': os.environ.get('INVOCATION_ID')}
    atomic(path, record)
    try:
      with subprocess.Popen(c['jobCommand']) as child:
        def forward(signum, frame):
          child.send_signal(signum)
        previous = {sig: signal.signal(sig, forward) for sig in (signal.SIGTERM, signal.SIGINT)}
        try:
          code = child.wait()
        finally:
          for sig, handler in previous.items():
            signal.signal(sig, handler)
    except OSError as error:
      code = 127
      record['launchError'] = type(error).__name__
    valid = False
    if code == 0:
      try:
        result = json.loads(command(c['resultCommand'], 45))
        valid = isinstance(result, dict) and result.get('completionValid') is True
      except Exception as error:
        record['validationError'] = type(error).__name__
    atomic(path, {**record, 'phase': 'finished', 'exitCode': code,
                  'completionValid': valid, 'finishedAtUtc': now()})
    return code if code >= 0 else 128 - code


def status(c):
  record = json.loads(Path(c['jobRecord']).read_text())
  if record.get('identity') != identity(c):
    raise ValueError('Job record identity mismatch')
  if record.get('phase') == 'finished':
    code, valid = record['exitCode'], record['completionValid']
    if type(code) is not int or type(valid) is not bool or not record.get('finishedAtUtc'):
      raise ValueError('Incomplete completion record')
    return {'jobId': c['jobId'], 'state': 'succeeded' if code == 0 else 'failed',
            'exitCode': code, 'completionValid': valid}
  if record.get('phase') != 'running' or not record.get('invocationId'):
    raise ValueError('Incomplete execution record')
  raw = command([c['systemctl'], '--user', 'show', c['jobUnit'],
                 '--property=LoadState,ActiveState,SubState,InvocationID'], 5)
  unit = dict(line.split('=', 1) for line in raw.decode().splitlines() if '=' in line)
  if (unit.get('LoadState') != 'loaded' or unit.get('InvocationID') != record['invocationId'] or
      unit.get('ActiveState') not in {'active', 'activating', 'deactivating'} or
      unit.get('SubState') == 'exited'):
    raise ValueError('Job unavailable without completion evidence')
  return {'jobId': c['jobId'], 'state': 'running'}


def main():
  os.umask(0o077)
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('action', choices=['run', 'status'])
  parser.add_argument('--config', required=True)
  args = parser.parse_args()
  try:
    c = json.loads(Path(args.config).read_text())
    if args.action == 'run':
      return run(c)
    print(json.dumps(status(c)))
    return 0
  except Exception as error:
    print(type(error).__name__, file=sys.stderr)
    return 1


if __name__ == '__main__':
  sys.exit(main())
