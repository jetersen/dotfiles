"""Keep background T3 credential reads from opening keyring unlock prompts."""
import os
import sys

import dbus


def check_keyring(bus):
    # Do not activate another daemon before desktop login.
    owner = bus.get_name_owner('org.freedesktop.secrets')
    properties = dbus.Interface(
        bus.get_object(owner, '/org/freedesktop/secrets/collection/login'),
        'org.freedesktop.DBus.Properties')
    if properties.Get('org.freedesktop.Secret.Collection', 'Locked'):
        raise RuntimeError('Desktop keyring is locked; run unlock-keyring in a terminal.')


def main():
    executable, *arguments = sys.argv[1:]
    if arguments[:2] == ['auth', 'token'] and not any(
            os.environ.get(name) for name in
            ('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN')):
        bus = dbus.bus.BusConnection(f'unix:path=/run/user/{os.getuid()}/bus')
        try:
            check_keyring(bus)
        finally:
            bus.close()
    os.execv(executable, [executable, *arguments])


if __name__ == '__main__':
    try:
        main()
    except (dbus.DBusException, RuntimeError, OSError) as error:
        sys.exit(f'gh: {error}')
