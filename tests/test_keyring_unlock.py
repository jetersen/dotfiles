import getpass
from importlib.machinery import SourceFileLoader
import importlib.util
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
import warnings

import dbus


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'home/dot_local/bin/executable_unlock-keyring'
loader = SourceFileLoader('keyring_unlock', str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)
guard_spec = importlib.util.spec_from_file_location('t3_gh', ROOT / 'nixos/packages/t3-gh.py')
guard = importlib.util.module_from_spec(guard_spec)
guard_spec.loader.exec_module(guard)


@unittest.skipUnless(shutil.which('gnome-keyring-daemon') and shutil.which('dbus-daemon'),
                     'requires GNOME Keyring and D-Bus')
class KeyringUnlockTests(unittest.TestCase):
  @classmethod
  def setUpClass(cls):
    temporary = tempfile.TemporaryDirectory(prefix='keyring-unlock-test-')
    cls.addClassCleanup(temporary.cleanup)
    cls.root = Path(temporary.name)
    configuration = cls.root / 'session.conf'
    configuration.write_text(f'''<busconfig>
      <type>session</type>
      <listen>unix:tmpdir={cls.root}</listen>
      <auth>EXTERNAL</auth>
      <policy context="default">
        <allow send_destination="*"/>
        <allow receive_sender="*"/>
        <allow own="*"/>
      </policy>
    </busconfig>''')
    broker = subprocess.Popen(
      ['dbus-daemon', '--config-file=' + str(configuration), '--nofork', '--print-address=1'],
      stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    cls.addClassCleanup(cls.stop, broker)
    cls.address = broker.stdout.readline().strip()
    if not cls.address:
      raise RuntimeError('Private D-Bus daemon failed to start: ' + broker.stderr.read())
    env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=cls.address,
               XDG_RUNTIME_DIR=str(cls.root / 'run'),
               XDG_DATA_HOME=str(cls.root / 'data'),
               XDG_CONFIG_HOME=str(cls.root / 'config'))
    for key in ('GNOME_KEYRING_CONTROL', 'GNOME_KEYRING_TEST_PATH', 'XDG_SESSION_ID'):
      env.pop(key, None)
    cls.control_directory = cls.root / 'run/keyring'
    cls.control_directory.mkdir(parents=True, mode=0o700)
    (cls.root / 'data/keyrings').mkdir(parents=True, mode=0o700)
    cls.daemon = subprocess.Popen(
      ['gnome-keyring-daemon', '--foreground', '--login',
       '--control-directory=' + str(cls.control_directory)],
      env=env, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cls.addClassCleanup(cls.stop, cls.daemon)
    cls.daemon.stdin.write(b'temporary-test-password')
    cls.daemon.stdin.close()
    deadline = time.monotonic() + 5
    while not (cls.control_directory / 'control').exists():
      if cls.daemon.poll() is not None or time.monotonic() > deadline:
        raise RuntimeError('Private keyring daemon failed to start')
      time.sleep(0.02)
    subprocess.run(
      ['gnome-keyring-daemon', '--start', '--components=secrets',
       '--control-directory=' + str(cls.control_directory)],
      env=env, check=True, timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

  @staticmethod
  def stop(process):
    if process.poll() is None:
      process.terminate()
      try:
        process.wait(timeout=5)
      except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)
    if process.stdout:
      process.stdout.close()
    if process.stderr:
      process.stderr.close()

  def setUp(self):
    self.bus = dbus.bus.BusConnection(self.address)
    self.addCleanup(self.bus.close)
    service = self.bus.get_object('org.freedesktop.secrets', helper.SERVICE_PATH)
    dbus.Interface(service, 'org.freedesktop.Secret.Service').Lock(
      [dbus.ObjectPath(helper.COLLECTION_PATH)])
    self.properties = dbus.Interface(
      self.bus.get_object('org.freedesktop.secrets', helper.COLLECTION_PATH),
      'org.freedesktop.DBus.Properties')
    self.assertTrue(self.locked())

  def locked(self):
    return bool(self.properties.Get(helper.COLLECTION_INTERFACE, 'Locked'))

  def unlock(self, password='temporary-test-password'):
    with patch.object(helper.getpass, 'getpass', return_value=password) as prompt:
      helper.unlock(self.bus)
    return prompt

  def test_correct_password_unlocks_desktop_service(self):
    self.unlock().assert_called_once()
    self.assertFalse(self.locked())

  def test_incorrect_password_fails_and_leaves_keyring_locked(self):
    with self.assertRaises(dbus.DBusException):
      self.unlock('deliberately-wrong-test-password')
    self.assertTrue(self.locked())

  def test_already_unlocked_does_not_prompt(self):
    self.unlock()
    self.unlock().assert_not_called()
    self.assertFalse(self.locked())

  def test_background_token_read_rejects_locked_keyring_without_prompt(self):
    with self.assertRaisesRegex(RuntimeError, 'run unlock-keyring'):
      guard.check_keyring(self.bus)
    self.assertTrue(self.locked())
    self.unlock()
    guard.check_keyring(self.bus)

  def test_background_guard_preserves_environment_tokens_and_other_commands(self):
    for arguments, environment in [
        (['auth', 'token'], {'GH_TOKEN': 'fixture-token'}),
        (['pr', 'list'], {}),
    ]:
      with self.subTest(arguments=arguments, environment=environment):
        with patch.dict(os.environ, environment, clear=True), \
             patch.object(guard.sys, 'argv', ['guard', '/real/gh', *arguments]), \
             patch.object(guard.dbus.bus, 'BusConnection') as connect, \
             patch.object(guard.os, 'execv') as execute:
          guard.main()
          connect.assert_not_called()
          execute.assert_called_once_with('/real/gh', ['/real/gh', *arguments])

  def test_replaced_control_socket_cannot_redirect_unlock(self):
    control = self.control_directory / 'control'
    original = self.control_directory / 'original-control'
    control.rename(original)
    try:
      with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as decoy:
        decoy.bind(str(control))
        decoy.listen(1)
        decoy.settimeout(0.02)
        self.unlock()
        self.assertFalse(self.locked())
        broker = dbus.Interface(
          self.bus.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus'),
          'org.freedesktop.DBus')
        self.assertEqual(broker.GetConnectionUnixProcessID(
          'org.freedesktop.secrets'), self.daemon.pid)
        with self.assertRaises(socket.timeout):
          decoy.accept()
    finally:
      control.unlink(missing_ok=True)
      original.rename(control)

  def test_no_terminal_does_not_fall_back_to_reading_stdin(self):
    def unavailable_terminal(*args, **kwargs):
      warnings.warn('No terminal', getpass.GetPassWarning)
      self.fail('getpass warning was not rejected')

    with patch.object(helper.getpass, 'getpass', side_effect=unavailable_terminal):
      with self.assertRaises(getpass.GetPassWarning):
        helper.unlock(self.bus)
    self.assertTrue(self.locked())


if __name__ == '__main__':
  unittest.main()
