"""One bounded, read-only status tick; persist before delivery, stop after webhook admission."""
import argparse
from contextlib import contextmanager
import datetime
import fcntl
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import resource
import selectors
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

STATES = {'running', 'succeeded', 'failed', 'cancelled', 'timed_out'}
ACKS = {'accepted', 'duplicate'}
SIGNATURE = {'header': 'x-t3-notify-signature', 'encoding': 'hex', 'prefix': 'sha256='}
# Stay inside T3's verified seven-day replay retention, including restart delays.
MAX_PENDING_AGE = datetime.timedelta(days=6)


class AdapterCommandError(RuntimeError):
  pass


class EndpointCommandError(RuntimeError):
  pass


def now():
  return datetime.datetime.now(datetime.timezone.utc).isoformat()


def log(event, **fields):
  print(json.dumps({'atUtc': now(), 'event': event, **fields}), flush=True)


def atomic(path, value):
  fd, name = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
  try:
    with os.fdopen(fd, 'w') as stream:
      json.dump(value, stream, sort_keys=True)
      stream.write('\n')
      stream.flush()
      os.fsync(stream.fileno())
    os.replace(name, path)
    directory = os.open(path.parent, os.O_DIRECTORY)
    try:
      os.fsync(directory)
    finally:
      os.close(directory)
  finally:
    if os.path.exists(name):
      os.unlink(name)


def command(argv, timeout, limit=65536):
  """Bound wall time and captured output; reap/kill this command's process group."""
  with subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        start_new_session=True) as process:
    try:
      deadline = time.monotonic() + timeout
      output = bytearray()
      with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while True:
          remaining = deadline - time.monotonic()
          if remaining <= 0 or not selector.select(remaining):
            raise TimeoutError()
          chunk = os.read(process.stdout.fileno(), 4096)
          if not chunk:
            break
          output.extend(chunk)
          if len(output) > limit:
            raise ValueError('Output limit')
      if process.wait(timeout=max(0.001, deadline - time.monotonic())):
        raise RuntimeError('Command failed')
      return bytes(output)
    finally:
      try:
        os.killpg(process.pid, signal.SIGKILL)
      except ProcessLookupError:
        pass
      process.wait()


def load_config(path):
  c = json.loads(Path(path).read_text())
  for key in ('jobId', 'scheduledTaskId', 'threadId', 'projectId'):
    if not isinstance(c[key], str) or not 1 <= len(c[key]) <= 256:
      raise ValueError('Invalid identity')
  if str(uuid.UUID(c['watchId'])) != c['watchId']:
    raise ValueError('Invalid watch ID')
  for key in ('adapterCommand', 'endpointCommand'):
    if (not isinstance(c[key], list) or not c[key] or
        any(not isinstance(a, str) or not a for a in c[key]) or
        not Path(c[key][0]).is_absolute()):
      raise ValueError('Absolute command required')
  if not Path(c['stateDirectory']).is_absolute():
    raise ValueError('Absolute state directory required')
  for key, default, maximum in (('adapterTimeout', 45, 60), ('endpointTimeout', 5, 10),
                               ('httpTimeout', 10, 15)):
    c.setdefault(key, default)
    if type(c[key]) not in (float, int) or not 0 < c[key] <= maximum:
      raise ValueError('Invalid timeout')
  c.setdefault('systemctl', shutil.which('systemctl'))
  if not c['systemctl'] or not Path(c['systemctl']).is_absolute():
    raise ValueError('Absolute systemctl required')
  if 'tailnetHttp' in c:
    raise ValueError('Remote HTTP is unsupported; use httpsOrigin')
  if 'httpsOrigin' in c:
    https_origin(c['httpsOrigin'])
  return c


def owner(c):
  return {k: c[k] for k in ('watchId', 'jobId', 'scheduledTaskId', 'threadId', 'projectId')}


def unit(c):
  return 't3-notify-' + c['watchId']


def description(c):
  return 'T3 completion notifier ' + c['watchId']


@contextmanager
def locked(c):
  root = Path(c['stateDirectory'])
  root.mkdir(parents=True, mode=0o700, exist_ok=True)
  if root.is_symlink() or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
    raise ValueError('Private state directory required')
  with (root / 'poll.lock').open('a') as lock:
    try:
      fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
      yield None
      return
    path = root / 'owner.json'
    if path.exists():
      if json.loads(path.read_text()) != owner(c):
        raise ValueError('State belongs to another watch')
    else:
      if any((root / name).exists() for name in ('pending-terminal.json', 'notified.json')):
        raise ValueError('Unowned state')
      atomic(path, owner(c))
    yield root


def event_from_status(c, status):
  if not isinstance(status, dict) or status.get('jobId') != c['jobId']:
    raise ValueError('Wrong job')
  state = status.get('state')
  if state not in STATES:
    raise ValueError('Unknown state')
  if state == 'running':
    return None
  valid = status.get('completionValid') is True
  code = status.get('exitCode')
  code = code if type(code) is int and -2147483648 <= code <= 2147483647 else None
  reason = 'terminal'
  if state == 'succeeded' and (not valid or code != 0):
    state, reason = 'failed', 'invalid_completion'
  # Explicit allowlist: no raw stdout, provider errors, URLs or arbitrary summaries.
  event = {**owner(c), 'event': 'job_terminal', 'status': state,
           'exitCode': code, 'completionValid': valid, 'reason': reason, 'observedAtUtc': now()}
  event['eventId'] = hashlib.sha256(json.dumps(event, sort_keys=True).encode()).hexdigest()
  return event


def validate_event(c, event):
  if not isinstance(event, dict) or any(event.get(k) != v for k, v in owner(c).items()):
    raise ValueError('Wrong pending identity')
  copy = dict(event)
  event_id = copy.pop('eventId', None)
  if (event_id != hashlib.sha256(json.dumps(copy, sort_keys=True).encode()).hexdigest() or
      event.get('event') != 'job_terminal' or event.get('status') not in STATES - {'running'}):
    raise ValueError('Invalid pending event')


def fetch(c):
  try:
    raw = command(c['adapterCommand'], c['adapterTimeout'])
  except Exception:
    raise AdapterCommandError() from None
  return json.loads(raw)


class NoRedirect(urllib.request.HTTPRedirectHandler):
  def redirect_request(self, *args):
    return None


def loopback_url(url):
  p = urllib.parse.urlsplit(url)
  if (p.scheme != 'http' or p.hostname not in {'127.0.0.1', '::1'} or not p.port or
      p.username is not None or p.password is not None or p.fragment or p.query or
      not p.path.startswith('/')):
    raise ValueError('Literal loopback HTTP endpoint required')
  return url


def https_origin(origin):
  p = urllib.parse.urlsplit(origin)
  if (p.scheme != 'https' or not p.hostname or p.path or p.query or p.fragment or
      p.username is not None or p.password is not None or
      any(ch.isspace() for ch in origin) or p.port == 0 or
      origin != 'https://' + p.netloc or p.netloc != p.netloc.lower()):
    raise ValueError('Exact HTTPS origin required')
  return origin


def endpoint_url(c, url):
  # Remote HTTPS is opt-in for one origin, never a wildcard allowlist.
  if 'tailnetHttp' in c:
    raise ValueError('Remote HTTP is unsupported; use httpsOrigin')
  if 'httpsOrigin' not in c:
    return loopback_url(url)
  expected = https_origin(c['httpsOrigin'])
  p = urllib.parse.urlsplit(url)
  if (p.scheme != 'https' or 'https://' + p.netloc != expected or not p.path or
      p.username is not None or p.password is not None or p.query or p.fragment or
      any(ch.isspace() for ch in url)):
    raise ValueError('Endpoint origin mismatch')
  return url


def resolve_credentials(c):
  # Resolver JSON contains credentials. Keep it in captured pipes and memory only.
  try:
    raw = command(c['endpointCommand'], c['endpointTimeout'], 16384)
  except Exception:
    raise EndpointCommandError() from None
  credentials = json.loads(raw)
  url = endpoint_url(c, credentials['url'])
  key = credentials.get('signingKey')
  if 'signingKey' in credentials and (not isinstance(key, str) or not 32 <= len(key.encode()) <= 4096):
    raise ValueError('Signing key must contain 32 to 4096 UTF-8 bytes')
  return url, key


def post(c, event):
  url, key = resolve_credentials(c)
  body = json.dumps(event, sort_keys=True).encode()
  headers = {'Content-Type': 'application/json'}
  if key is not None:
    headers[SIGNATURE['header']] = SIGNATURE['prefix'] + hmac.new(key.encode(), body, hashlib.sha256).hexdigest()
  request = urllib.request.Request(url, method='POST', data=body, headers=headers)
  opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
  with opener.open(request, timeout=c['httpTimeout']) as response:
    outcome = response.headers.get('x-t3-hook-outcome')
    # Do not consume a potentially unbounded or slow response body.
    if response.status != 202 or outcome not in ACKS:
      raise RuntimeError('No positive acknowledgement')
  return outcome


def stop(c):
  timer = unit(c) + '.timer'
  raw = command([c['systemctl'], '--user', 'show', timer, '--property=LoadState,Transient,Description,Unit'], 5)
  fields = dict(line.split('=', 1) for line in raw.decode().splitlines() if '=' in line)
  if fields.get('LoadState') == 'not-found':
    return
  if (fields.get('Transient') != 'yes' or fields.get('Description') != description(c) or
      fields.get('Unit') != unit(c) + '.service'):
    raise ValueError('Timer ownership mismatch')
  command([c['systemctl'], '--user', 'stop', timer], 5)
  state = command([c['systemctl'], '--user', 'show', timer, '--property=ActiveState', '--value'], 5)
  if state.strip() not in {b'inactive', b'failed', b''}:
    raise RuntimeError('Timer still active')


def check_once(c, fetch_status=fetch, deliver=post, stop_timer=stop):
  with locked(c) as root:
    if root is None:
      return 'locked'
    pending = root / 'pending-terminal.json'
    sent = root / 'notified.json'
    if sent.exists():
      receipt = json.loads(sent.read_text())
      event = json.loads(pending.read_text())
      validate_event(c, event)
      if (receipt.get('owner') != owner(c) or receipt.get('eventId') != event['eventId'] or
          receipt.get('outcome') not in ACKS):
        raise ValueError('Invalid receipt')
      stop_timer(c)
      return 'already_notified'
    if pending.exists():
      event = json.loads(pending.read_text())
      validate_event(c, event)
    else:
      status = fetch_status(c)
      event = event_from_status(c, status)
      atomic(root / 'last-check.json', {'atUtc': now(), 'jobId': c['jobId'], 'state': status['state']})
      if event is None:
        log('job_running')
        return 'running'
      atomic(pending, event)
      log('terminal_detected', status=event['status'])
    observed = datetime.datetime.fromisoformat(event['observedAtUtc'])
    if observed.tzinfo is None:
      raise ValueError('Pending timestamp must include timezone')
    if datetime.datetime.now(datetime.timezone.utc) - observed >= MAX_PENDING_AGE:
      log('delivery_expired_needs_reconciliation')
      stop_timer(c)
      return 'expired'
    outcome = deliver(c, event)
    if outcome not in ACKS:
      raise RuntimeError('No positive acknowledgement')
    atomic(sent, {'atUtc': now(), 'owner': owner(c), 'eventId': event['eventId'], 'outcome': outcome,
                  'dispatchVerified': False})
    log('webhook_accepted', status=event['status'], outcome=outcome)
    stop_timer(c)
    return 'notified'


def start(c, config_path, interval):
  if not re.fullmatch(r'[1-9][0-9]*(s|min|h)', interval):
    raise ValueError('Use a positive systemd interval such as 5min')
  resolve_credentials(c)  # Check transport/auth before a quiet active tick can hide a bad resolver.
  with locked(c) as root:
    if root is None or (root / 'notified.json').exists():
      raise ValueError('Watch busy or already delivered')
    # No --replace: a collision must not overwrite another service/timer.
    command(['systemd-run', '--user', '--unit=' + unit(c), '--description=' + description(c),
             '--on-active=5s', '--on-unit-inactive=' + interval,
             '--timer-property=AccuracySec=1s', '--property=Type=exec',
             '--property=RuntimeMaxSec=120', '--property=TimeoutStopSec=5',
             '--property=KillMode=control-group', '--property=UMask=0077',
             '--property=LimitCORE=0', '--property=StandardError=null',
             '--property=StandardOutput=append:' + str(root / 'watcher.log'),
             sys.executable, str(Path(__file__).resolve()), 'tick', '--config',
             str(Path(config_path).resolve())], 10)
  log('timer_started', timerUnit=unit(c) + '.timer', interval=interval)


def main(argv=None):
  resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
  os.umask(0o077)
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('action', choices=['tick', 'start', 'preflight'])
  parser.add_argument('--config', required=True, help='Non-secret JSON config')
  parser.add_argument('--interval', default='5min', help='Local timer cadence (start only)')
  args = parser.parse_args(argv)
  try:
    c = load_config(args.config)
    if args.action == 'preflight':
      resolve_credentials(c)
      log('credential_preflight_ok')
    elif args.action == 'start':
      start(c, args.config, args.interval)
    else:
      check_once(c)
  except Exception as error:
    # Exception text can include the webhook URL. No tracebacks or raw CLI output.
    fields = {'exceptionType': type(error).__name__}
    if isinstance(error, urllib.error.HTTPError):
      fields['httpStatus'] = error.code
    log('poll_failed_retry_next_tick', **fields)
    return 1
  return 0


if __name__ == '__main__':
  raise SystemExit(main())
