"""Keep Espanso's evdev keymap in sync with niri, including IPC layout changes."""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys


def layout_codes(source):
    matches = re.findall(r'^\s*layout "([^"]+)"', source, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError('Expected one managed niri keyboard layout declaration')
    return matches[0].split(',')


def write_config(root, codes, index):
    layout = codes[index]
    settings = {
        'keyboard_layout': {'layout': layout},
        'backend': 'clipboard',
        'search_shortcut': 'off',  # Alt+Space belongs to niri's layout switcher.
        'toggle_key': 'OFF',
        'show_notifications': False,
        'show_icon': False,
        'preserve_clipboard': True,
    }
    target = root / 'config/default.yml'
    text = json.dumps(settings) + '\n'
    if target.exists() and target.read_text() == text:
        return
    temporary = target.with_suffix('.tmp')
    temporary.write_text(text)
    temporary.replace(target)


def watch(root, codes, source, ready):
    initialized = False
    for line in source:
        event = json.loads(line)
        if 'KeyboardLayoutsChanged' in event:
            layouts = event['KeyboardLayoutsChanged']['keyboard_layouts']
            if len(layouts['names']) != len(codes):
                raise ValueError('Running keyboard layouts differ from managed niri configuration')
            write_config(root, codes, layouts['current_idx'])
            if not initialized:
                initialized = True
                ready()
        elif 'KeyboardLayoutSwitched' in event:
            write_config(root, codes, event['KeyboardLayoutSwitched']['idx'])


def main():
    os.umask(0o077)
    root = Path(os.environ['XDG_RUNTIME_DIR']) / 'espanso-niri'
    (root / 'config').mkdir(parents=True, exist_ok=True)
    matches = root / 'match'
    if not matches.exists():
        matches.symlink_to(Path.home() / '.config/espanso/match')
    codes = layout_codes(Path(sys.argv[1]).read_text())
    with socket.socket(socket.AF_UNIX) as connection:
        connection.connect(os.environ['NIRI_SOCKET'])
        connection.sendall(b'"EventStream"\n')
        with connection.makefile() as stream:
            reply = json.loads(next(stream))
            if reply != {'Ok': 'Handled'}:
                raise RuntimeError(f'niri rejected event stream: {reply}')
            watch(root, codes, stream,
                  lambda: subprocess.run(['systemd-notify', '--ready'], check=True))
    raise RuntimeError('niri event stream disconnected')


if __name__ == '__main__':
    main()
