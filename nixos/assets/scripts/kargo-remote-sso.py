#!/usr/bin/env python3
"""Log in to Kargo through a remote Linux desktop browser over Tailscale."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

REMOTE_SCRIPT = r'''
import json, os, pathlib, subprocess, sys
options = json.loads(sys.argv[1])
path = pathlib.Path(os.environ.get('XDG_CONFIG_HOME') or pathlib.Path.home() / '.config') / 'kargo/config'
def load():
  if not path.exists():
    return {}
  return json.loads(subprocess.check_output(['yq', '-o=json', '.', str(path)], timeout=10)) or {}
settings = load()
server = options['server'] or settings.get('apiAddress')
if not server:
  raise ValueError('specify --server for the first remote login')
if not options['copy_only']:
  session = json.loads(subprocess.check_output(
    ['systemctl', '--user', 'show-environment', '--output=json'], timeout=5))
  env = os.environ.copy()
  for key in ('WAYLAND_DISPLAY', 'DISPLAY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS',
              'XDG_CURRENT_DESKTOP', 'XDG_SESSION_TYPE', 'PATH', 'BROWSER'):
    if key in session:
      env[key] = session[key]
  subprocess.run(['kargo', 'login', server, '--sso', '--port', str(options['port'])],
                 env=env, stdout=sys.stderr, check=True, timeout=240)
  settings = load()
if settings.get('apiAddress', '').rstrip('/') != server.rstrip('/'):
  raise ValueError('remote login does not use the requested server')
if settings.get('authMethod') != 'sso' or not settings.get('bearerToken'):
  raise ValueError('remote configuration has no SSO token')
print(json.dumps({key: settings[key] for key in (
  'apiAddress', 'authMethod', 'bearerToken', 'refreshToken', 'insecureSkipTLSVerify',
  'callbackPort') if key in settings}))
'''


def read_config(path):
  if not path.exists():
    return {}
  return json.loads(subprocess.check_output(['yq', '-o=json', '.', str(path)], timeout=10)) or {}


def merge_config(settings, bundle):
  if (not isinstance(bundle, dict) or not bundle.get('apiAddress')
      or bundle.get('authMethod') != 'sso' or not bundle.get('bearerToken')):
    raise ValueError('received an incomplete SSO configuration')
  # Kargo stores one login. Preserve local preferences only for the same server,
  # and replace authentication fields so an old refresh token cannot survive.
  merged = {key: bundle[key] for key in (
    'apiAddress', 'authMethod', 'bearerToken', 'refreshToken', 'insecureSkipTLSVerify',
    'callbackPort') if key in bundle}
  if settings.get('apiAddress', '').rstrip('/') == bundle['apiAddress'].rstrip('/'):
    if 'project' in settings:
      merged['project'] = settings['project']
  return merged


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('host', help='remote browser host, for example framework')
  parser.add_argument('--server', help='Kargo server URL or hostname; defaults to the remote login server')
  parser.add_argument('--port', type=int, default=8086, help='remote SSO callback port (default: 8086)')
  parser.add_argument('--copy-only', action='store_true', help='copy without opening the remote browser')
  parser.add_argument('--config', type=Path,
                      default=Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'kargo/config',
                      help='local Kargo configuration path')
  args = parser.parse_args()
  if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.@-]*', args.host):
    parser.error('host must be a Tailscale hostname or user@hostname')
  if not 0 <= args.port <= 65535:
    parser.error('port must be between 0 and 65535')
  if args.server:
    if not args.server.startswith(('http://', 'https://')):
      args.server = 'https://' + args.server
    args.server = args.server.rstrip('/')
  options = {key: getattr(args, key) for key in ('server', 'port', 'copy_only')}
  response = subprocess.run(
    ['tailscale', 'ssh', args.host, '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8',
     '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=2',
     shlex.join(['python3', '-', json.dumps(options)])],
    input=REMOTE_SCRIPT, stdout=subprocess.PIPE, text=True, check=True,
    timeout=30 if args.copy_only else 270,
  ).stdout
  bundle = json.loads(response)
  config = args.config.expanduser()
  config.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
  lock = os.open(config.with_name('.remote-sso.lock'), os.O_CREAT | os.O_RDWR, 0o600)
  with os.fdopen(lock, 'w') as stream:
    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
    settings = merge_config(read_config(config), bundle)
    content = subprocess.check_output(
      ['yq', '-p=json', '-o=yaml', '-P', '.'], input=json.dumps(settings), text=True, timeout=10)
    descriptor, temporary = tempfile.mkstemp(prefix='.remote-sso-', dir=config.parent)
    try:
      with os.fdopen(descriptor, 'w') as output:
        output.write(content)
      os.replace(temporary, config)
    finally:
      if os.path.exists(temporary):
        os.unlink(temporary)
  print(f"Kargo login for {bundle['apiAddress']!r} copied from {args.host}.")


if __name__ == '__main__':
  try:
    main()
  except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
    # Do not include transfer output, which contains authentication tokens.
    print(f'kargo-remote-sso: {error}', file=sys.stderr)
    sys.exit(1)
