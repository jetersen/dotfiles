#!/usr/bin/env python3
"""Unlock the existing GNOME login keyring from a local or SSH terminal."""

import argparse
import contextlib
import getpass
import os
import sys
import warnings

import dbus


SERVICE_PATH = '/org/freedesktop/secrets'
COLLECTION_PATH = SERVICE_PATH + '/collection/login'
COLLECTION_INTERFACE = 'org.freedesktop.Secret.Collection'


def unlock(bus):
  # Pin every call to the desktop service's current owner. A second daemon can
  # replace the filesystem control socket without owning this D-Bus service.
  owner = bus.get_name_owner('org.freedesktop.secrets')
  service = bus.get_object(owner, SERVICE_PATH)
  properties = dbus.Interface(
    bus.get_object(owner, COLLECTION_PATH), 'org.freedesktop.DBus.Properties')
  if not properties.Get(COLLECTION_INTERFACE, 'Locked'):
    return

  # Refuse getpass's fallback to echoed stdin when SSH has no terminal.
  with warnings.catch_warnings():
    warnings.simplefilter('error', getpass.GetPassWarning)
    password = getpass.getpass('Desktop keyring password: ').encode()
  _, session = dbus.Interface(service, 'org.freedesktop.Secret.Service').OpenSession(
    'plain', dbus.String('', variant_level=1))
  try:
    secret = dbus.Struct(
      (session, dbus.ByteArray(b''), dbus.ByteArray(password), 'text/plain; charset=utf8'),
      signature='oayays')
    dbus.Interface(
      service, 'org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface'
    ).UnlockWithMasterPassword(COLLECTION_PATH, secret, timeout=15)
    if properties.Get(COLLECTION_INTERFACE, 'Locked'):
      raise RuntimeError('The desktop login keyring is still locked.')
  finally:
    # Closing a session must not hide an incorrect-password error.
    with contextlib.suppress(dbus.DBusException):
      dbus.Interface(
        bus.get_object(owner, session), 'org.freedesktop.Secret.Session').Close()


def main():
  argparse.ArgumentParser(prog='unlock-keyring', description=__doc__).parse_args()
  # SSH may inherit a different session bus. Use the logged-in user's desktop
  # bus explicitly, without activating another keyring daemon.
  bus = dbus.bus.BusConnection(f'unix:path=/run/user/{os.getuid()}/bus')
  try:
    unlock(bus)
  finally:
    bus.close()
  print('Desktop login keyring verified unlocked.')


if __name__ == '__main__':
  try:
    main()
  except (getpass.GetPassWarning, EOFError):
    sys.exit('unlock-keyring: a terminal is required; use ssh -t HOST unlock-keyring')
  except KeyboardInterrupt:
    sys.exit(130)
  except (dbus.DBusException, RuntimeError, OSError) as error:
    sys.exit(f'unlock-keyring: {error}')
