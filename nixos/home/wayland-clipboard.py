"""Run wl-clipboard against the user's desktop, including from SSH/mosh."""

import json
import os
import subprocess
import sys


def desktop_environment(env):
  env = env.copy()
  if not env.get('WAYLAND_DISPLAY') or not env.get('XDG_RUNTIME_DIR'):
    # Tailscale SSH may omit even XDG_RUNTIME_DIR. The user bus lives here.
    env.setdefault('XDG_RUNTIME_DIR', f'/run/user/{os.getuid()}')
    try:
      session = json.loads(subprocess.check_output(
        ['systemctl', '--user', 'show-environment', '--output=json'],
        env=env, timeout=5))
      for key in ('WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR'):
        if not env.get(key) and session.get(key):
          env[key] = session[key]
    except (OSError, ValueError, subprocess.SubprocessError):
      # Let wl-clipboard report its usual error when no desktop is available.
      pass
  return env


if __name__ == '__main__':
  os.execve(sys.argv[1], sys.argv[1:], desktop_environment(os.environ))
