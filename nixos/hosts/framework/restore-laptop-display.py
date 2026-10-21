"""Recover an undocked panel without waiting for DMS's rendering/event loop."""

import json
import subprocess
import sys


def restore_from_events(events, niri):
  for line in events:
    outputs = json.loads(line).get('OutputsChanged', {}).get('outputs', {})
    # Niri keeps disabled, connected outputs in this map. DPMS sleep retains
    # their logical configuration, so idle blanking does not trigger recovery.
    if set(outputs) != {'eDP-1'} or outputs['eDP-1'].get('logical') is not None:
      continue
    print('Undocked with the laptop panel disabled; enabling eDP-1', flush=True)
    subprocess.run([niri, 'msg', 'output', 'eDP-1', 'on'], check=True, timeout=5)


def main(niri):
  # The stream includes the initial output state, covering service restarts.
  with subprocess.Popen([niri, 'msg', '-j', 'event-stream'],
                        stdout=subprocess.PIPE, text=True) as stream:
    try:
      restore_from_events(stream.stdout, niri)
    finally:
      stream.terminate()
      stream.wait(timeout=5)
  # Reconnect through systemd if the compositor or event stream was replaced.
  raise RuntimeError('Niri event stream disconnected')


if __name__ == '__main__':
  main(sys.argv[1])
