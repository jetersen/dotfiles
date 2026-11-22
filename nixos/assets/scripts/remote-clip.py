#!/usr/bin/env python3
"""Fetch an image or plain text from another Linux Wayland session over SSH."""

import argparse
import json
import mimetypes
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

REMOTE_SCRIPT = r'''
import json, os, subprocess, sys
session = json.loads(subprocess.check_output(
  ['systemctl', '--user', 'show-environment', '--output=json'], timeout=5))
env = os.environ.copy()
for key in ('WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR', 'DISPLAY', 'PATH'):
  if key in session:
    env[key] = session[key]
types = subprocess.check_output(['wl-paste', '--list-types'], env=env, timeout=5).decode().splitlines()
requested = sys.argv[1]
images = [value for value in types if value.startswith('image/')]
if 'image/png' in images:
  images.remove('image/png')
  images.insert(0, 'image/png')
texts = [value for preferred in ('text/plain;charset=utf-8', 'text/plain', 'utf8_string')
         for value in types if value.lower() == preferred]
choices = images + texts if requested == 'auto' else images if requested == 'image' else texts
if not choices:
  sys.exit('remote-clip: no supported clipboard content for ' + requested)
mime = choices[0]
data = subprocess.check_output(['wl-paste', '--no-newline', '--type', mime], env=env, timeout=10)
if mime.startswith('image/') and not data:
  sys.exit('remote-clip: received an empty image')
if mime.lower() == 'utf8_string':
  mime = 'text/plain;charset=utf-8'
elif mime.lower().startswith('text/plain'):
  mime = mime.lower()
sys.stdout.buffer.write(mime.encode() + b'\n' + data)
'''


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('host', help='Tailscale host, for example framework or rocket')
  parser.add_argument('--type', choices=('auto', 'image', 'text'), default='auto',
                      help='auto prefers images when both are offered')
  parser.add_argument('-o', '--output', help='file, existing directory, or - for raw stdout')
  parser.add_argument('--no-copy', action='store_true', help='save without changing the local clipboard')
  args = parser.parse_args()
  if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.@-]*', args.host):
    parser.error('host must be a Tailscale hostname or user@hostname')
  response = subprocess.run(
    ['tailscale', 'ssh', args.host, '-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8',
     '-o', 'ServerAliveInterval=5', '-o', 'ServerAliveCountMax=2',
     shlex.join(['python3', '-', args.type])],
    input=REMOTE_SCRIPT.encode(), stdout=subprocess.PIPE, check=True, timeout=30,
  ).stdout
  mime_bytes, separator, data = response.partition(b'\n')
  mime = mime_bytes.decode()
  if not separator or not re.fullmatch(r'image/[\w.+-]+|text/plain(?:;charset=utf-8)?', mime):
    raise ValueError('remote returned an unsupported clipboard type')
  if mime.startswith('image/') and not data:
    raise ValueError('remote returned an empty image')
  if args.output == '-':
    sys.stdout.buffer.write(data)
    return
  extension = '.txt' if mime.startswith('text/') else mimetypes.guess_extension(mime) or '.img'
  if args.output:
    target = Path(args.output).expanduser()
    if target.is_dir() or args.output.endswith('/'):
      target.mkdir(parents=True, exist_ok=True)
      descriptor, filename = tempfile.mkstemp(prefix='remote-clip-', suffix=extension, dir=target)
      os.close(descriptor)
      target = Path(filename)
  else:
    directory = tempfile.mkdtemp(prefix='remote-clip-', dir=os.environ.get('XDG_RUNTIME_DIR'))
    target = Path(directory) / ('clipboard' + extension)
  target.parent.mkdir(parents=True, exist_ok=True)
  descriptor, temporary = tempfile.mkstemp(prefix='.remote-clip-', dir=target.parent)
  try:
    with os.fdopen(descriptor, 'wb') as stream:
      stream.write(data)
    os.replace(temporary, target)
  finally:
    if os.path.exists(temporary):
      os.unlink(temporary)
  if not args.no_copy:
    try:
      env = os.environ.copy()
      if not env.get('WAYLAND_DISPLAY'):
        session = json.loads(subprocess.check_output(
          ['systemctl', '--user', 'show-environment', '--output=json'], timeout=5))
        for key in ('WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR', 'DISPLAY'):
          if key in session:
            env[key] = session[key]
      # wl-copy forks a clipboard owner; do not wait for that child to release stdout.
      subprocess.run(['wl-copy', '--type', mime], input=data, env=env,
                     stdout=subprocess.DEVNULL, check=True, timeout=10)
    except (OSError, subprocess.SubprocessError) as error:
      print(f'remote-clip: saved {target}, but local copy failed: {error}', file=sys.stderr)
  print(target)


if __name__ == '__main__':
  try:
    main()
  except (OSError, ValueError, subprocess.SubprocessError) as error:
    print(f'remote-clip: {error}', file=sys.stderr)
    sys.exit(1)
