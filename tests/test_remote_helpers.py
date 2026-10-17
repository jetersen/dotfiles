"""Exercise shared helpers with synthetic clipboards/configs and a local SSH stand-in.

Requires python3 and Mike Farah yq v4. No real clipboard, VPN, or network access.
"""

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIP = ROOT / 'home/dot_local/bin/executable_remote-clip'
ARGO = ROOT / 'home/dot_local/bin/executable_argocd-remote-sso'
MOCK = r'''#!/usr/bin/env python3
import base64, json, os, pathlib, shlex, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
if name == 'tailscale':
  assert sys.argv[1] == 'ssh'
  pathlib.Path(os.environ['SSH_CALLED']).touch()
  if os.environ.get('SSH_FAIL'):
    sys.stdout.write('image/png\npartial')
    sys.exit(255)
  command = shlex.split(sys.argv[-1])
  env = dict(os.environ, HOME=os.environ['REMOTE_HOME'])
  result = subprocess.run([sys.executable] + command[1:], input=sys.stdin.buffer.read(), env=env)
  sys.exit(result.returncode)
elif name == 'systemctl':
  print(json.dumps({'WAYLAND_DISPLAY': 'wayland-mock', 'XDG_RUNTIME_DIR': os.environ['TEST_RUNTIME']}))
elif name == 'wl-paste':
  if '--list-types' in sys.argv:
    print('\n'.join(json.loads(os.environ['CLIP_TYPES'])))
  else:
    pathlib.Path(os.environ['MIME_LOG']).write_text(sys.argv[-1])
    sys.stdout.buffer.write(base64.b64decode(os.environ['CLIP_DATA']))
elif name == 'wl-copy':
  assert os.environ['WAYLAND_DISPLAY'] == 'wayland-mock'
  pathlib.Path(os.environ['COPY_LOG']).write_bytes(sys.stdin.buffer.read())
elif name == 'openvpn3':
  print('Config name: ' + os.environ.get('VPN_PROFILE', 'moviestarplanet'))
  print('Status: ' + os.environ.get('VPN_STATUS', 'Connection, Client connected'))
elif name == 'argocd':
  pathlib.Path(os.environ['LOGIN_LOG']).write_text(json.dumps(sys.argv[1:]))
  config = pathlib.Path.home() / '.config/argocd/config'
  settings = json.loads(config.read_text())
  name = sys.argv[sys.argv.index('--name') + 1]
  settings['contexts'] = [{'name': name, 'server': sys.argv[2], 'user': 'remote-user'}]
  settings['current-context'] = name
  settings['users'][0]['auth-token'] = 'new-synthetic-token'
  config.write_text(json.dumps(settings))
'''


class RemoteHelpersTests(unittest.TestCase):
  def setUp(self):
    self.temporary = tempfile.TemporaryDirectory()
    self.addCleanup(self.temporary.cleanup)
    self.root = Path(self.temporary.name)
    self.bin = self.root / 'bin'
    self.bin.mkdir()
    self.home = self.root / 'local'
    self.remote = self.root / 'remote'
    self.runtime = self.root / 'runtime'
    for directory in (self.home, self.remote, self.runtime):
      directory.mkdir(mode=0o700)
    for name in ('tailscale', 'systemctl', 'wl-paste', 'wl-copy', 'openvpn3', 'argocd'):
      command = self.bin / name
      command.write_text(MOCK)
      command.chmod(0o755)
    self.env = dict(os.environ, HOME=str(self.home), REMOTE_HOME=str(self.remote),
                    PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                    XDG_RUNTIME_DIR=str(self.runtime), TEST_RUNTIME=str(self.runtime),
                    SSH_CALLED=str(self.root / 'ssh-called'), MIME_LOG=str(self.root / 'mime'),
                    COPY_LOG=str(self.root / 'copy'), LOGIN_LOG=str(self.root / 'login'),
                    CLIP_TYPES=json.dumps(['text/plain;charset=utf-8']),
                    CLIP_DATA=base64.b64encode(b'hello\n').decode())
    self.env.pop('WAYLAND_DISPLAY', None)
    self.env.pop('DISPLAY', None)

  def run_helper(self, path, *args):
    return subprocess.run([sys.executable, str(path), *args], env=self.env, capture_output=True)

  def clipboard(self, types, data):
    self.env['CLIP_TYPES'] = json.dumps(types)
    self.env['CLIP_DATA'] = base64.b64encode(data).decode()

  def remote_config(self):
    config = self.remote / '.config/argocd/config'
    config.parent.mkdir(parents=True)
    config.write_text(json.dumps({
      'current-context': 'work',
      'contexts': [{'name': 'work', 'server': 'argo.example', 'user': 'remote-user'}],
      'servers': [{'server': 'argo.example', 'grpc-web': True}],
      'users': [{'name': 'remote-user', 'auth-token': 'synthetic-token'}],
    }))

  def local_config(self, settings):
    path = self.home / '.config/argocd/config'
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps(settings))
    return path

  def read_yaml(self, path):
    return json.loads(subprocess.check_output(['yq', '-o=json', '.', str(path)]))

  def test_text_bytes_copy_and_private_file(self):
    data = 'text with accents æøå\n\n'.encode()
    self.clipboard(['text/plain;charset=UTF-8'], data)
    result = self.run_helper(CLIP, 'framework')
    self.assertEqual(result.returncode, 0, result.stderr)
    target = Path(result.stdout.decode().strip())
    self.assertEqual(target.read_bytes(), data)
    self.assertEqual((self.root / 'copy').read_bytes(), data)
    self.assertEqual(target.stat().st_mode & 0o777, 0o600)
    self.assertEqual(target.parent.stat().st_mode & 0o777, 0o700)
    self.assertEqual(target.suffix, '.txt')

  def test_image_preference_and_binary_stdout(self):
    data = b'\x89PNG\r\n\x1a\n\0binary\n'
    self.clipboard(['text/plain', 'image/jpeg', 'image/png'], data)
    result = self.run_helper(CLIP, 'framework', '-o', '-')
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertEqual(result.stdout, data)
    self.assertEqual((self.root / 'mime').read_text(), 'image/png')
    self.assertFalse((self.root / 'copy').exists())

  def test_force_text_and_empty_text(self):
    self.clipboard(['image/png', 'text/plain'], b'')
    result = self.run_helper(CLIP, 'rocket', '--type', 'text', '--no-copy')
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertEqual(Path(result.stdout.decode().strip()).read_bytes(), b'')
    self.assertEqual((self.root / 'mime').read_text(), 'text/plain')

  def test_failed_transfer_preserves_target(self):
    target = self.home / 'existing'
    target.write_bytes(b'keep')
    self.env['SSH_FAIL'] = '1'
    result = self.run_helper(CLIP, 'framework', '-o', str(target))
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(target.read_bytes(), b'keep')

  def test_unsupported_clipboard_and_invalid_host(self):
    self.clipboard(['application/octet-stream'], b'unknown')
    result = self.run_helper(CLIP, 'framework', '--no-copy')
    self.assertNotEqual(result.returncode, 0)
    result = self.run_helper(CLIP, '-oProxyCommand=bad')
    self.assertNotEqual(result.returncode, 0)

  def test_copy_context_uses_references_and_preserves_other_state(self):
    self.remote_config()
    path = self.local_config({
      'current-context': 'personal', 'custom': 'preserve',
      'contexts': [{'name': 'personal', 'server': 'other.example', 'user': 'remote-user'}],
      'servers': [{'server': 'other.example'}],
      'users': [{'name': 'remote-user', 'auth-token': 'local-token'}],
    })
    args = ('framework', '--vpn-profile', 'moviestarplanet', '--copy-only')
    result = self.run_helper(ARGO, *args)
    self.assertEqual(result.returncode, 0, result.stderr)
    settings = self.read_yaml(path)
    self.assertEqual(settings['custom'], 'preserve')
    self.assertEqual(settings['current-context'], 'work')
    self.assertEqual(len(settings['contexts']), 2)
    users = {user['name']: user['auth-token'] for user in settings['users']}
    self.assertEqual(users['remote-user'], 'local-token')
    imported = next(context for context in settings['contexts'] if context['name'] == 'work')
    self.assertEqual(users[imported['user']], 'synthetic-token')
    self.assertEqual(path.stat().st_mode & 0o777, 0o600)
    self.assertFalse((self.root / 'login').exists())
    before = path.read_bytes()
    self.assertEqual(self.run_helper(ARGO, *args).returncode, 0)
    self.assertEqual(path.read_bytes(), before)

  def test_browser_login_exports_new_context(self):
    self.remote_config()
    result = self.run_helper(ARGO, 'framework', '--vpn-profile', 'moviestarplanet',
                             '--server', 'argo.example')
    self.assertEqual(result.returncode, 0, result.stderr)
    login = json.loads((self.root / 'login').read_text())
    self.assertIn('--sso-launch-browser', login)
    settings = self.read_yaml(self.home / '.config/argocd/config')
    self.assertEqual(settings['current-context'], 'argo.example')
    self.assertEqual(settings['users'][0]['auth-token'], 'new-synthetic-token')
    self.assertNotIn(b'synthetic-token', result.stdout + result.stderr)

  def test_browser_login_preserves_current_context_name(self):
    self.remote_config()
    result = self.run_helper(ARGO, 'framework', '--vpn-profile', 'moviestarplanet')
    self.assertEqual(result.returncode, 0, result.stderr)
    settings = self.read_yaml(self.home / '.config/argocd/config')
    self.assertEqual(settings['current-context'], 'work')
    self.assertEqual(settings['users'][0]['auth-token'], 'new-synthetic-token')

  def test_vpn_failure_does_not_start_transfer(self):
    self.env['VPN_STATUS'] = 'Disconnected'
    result = self.run_helper(ARGO, 'framework', '--vpn-profile', 'moviestarplanet')
    self.assertNotEqual(result.returncode, 0)
    self.assertFalse((self.root / 'ssh-called').exists())

  def test_bad_argo_transfer_preserves_config(self):
    path = self.local_config({'custom': 'preserve'})
    before = path.read_bytes()
    self.env['SSH_FAIL'] = '1'
    result = self.run_helper(ARGO, 'framework', '--vpn-profile', 'moviestarplanet', '--copy-only')
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(path.read_bytes(), before)

  def test_conflicting_shared_server_is_rejected(self):
    self.remote_config()
    path = self.local_config({
      'contexts': [{'name': 'other', 'server': 'argo.example', 'user': 'other'}],
      'servers': [{'server': 'argo.example', 'grpc-web': False}],
      'users': [{'name': 'other', 'auth-token': 'keep'}],
    })
    before = path.read_bytes()
    result = self.run_helper(ARGO, 'framework', '--vpn-profile', 'moviestarplanet', '--copy-only')
    self.assertNotEqual(result.returncode, 0)
    self.assertEqual(path.read_bytes(), before)


if __name__ == '__main__':
  unittest.main()
