"""Exclusive DNS ownership for Framework's experimental Linux multinet build.

Native recovery is a separate systemd job. Mutable credentials are never rolled
back: each start uses the latest saved explicit selection, not the catalog.
"""
import base64
import fcntl
import json
import ipaddress
import os
from pathlib import Path
import re
import subprocess
import sys
import time

RUN = Path('/run/tailscale-multinet')
MARKER = RUN / 'owns-dns'
VERIFIED = RUN / 'native-verified'
CONFIRMED = RUN / 'confirmed'
STATE = Path('/var/lib/tailscale-multi-profile-test/tailscaled.state')
NM_DNS = Path('/run/NetworkManager/no-stub-resolv.conf')
NATIVE = ('work-tailnet-netns', 'tailscaled', 'tailscaled-work',
          'work-tailnet-peer-dns', 'work-tailnet-dns', 'work-tailnet',
          'homelab-dns-resolv', 'homelab-dns-resolv.path', 'homelab-portal-dns', 'dnsdist')
GUARDS = (*NATIVE, 'tailscaled-set', 'tailscaled-autoconnect')
DAEMON = 'tailscale-multi-profile.service'
NM = 'org.freedesktop.NetworkManager'
ROOT = '/org/freedesktop/NetworkManager'


def command(*args, check=True):
  return subprocess.run(args, check=check, text=True, capture_output=True, timeout=90).stdout


def ctl(*args):
  return command('systemctl', *args)


def active(unit):
  return command('systemctl', 'show', unit, '-p', 'ActiveState', '--value').strip()


def require(value, message):
  if not value:
    raise RuntimeError(message)


def cli(*args):
  return command(os.environ['MULTINET_PACKAGE'] + '/bin/tailscale',
                 '--socket=/run/tailscale/tailscaled.sock', *args)


def selection(path=STATE):
  state = json.loads(path.read_bytes())
  def decode(key):
    return json.loads(base64.b64decode(state[key], validate=True))
  # Do not print state or keys in errors.
  selected = decode('_profile-network')
  require(selected['primary'] == '2ac3' and selected['secondary'] == ['30a1']
          and selected['preferred'] in ('2ac3', '30a1'), 'unexpected explicit profile selection')
  catalog = decode('_profiles')
  require(base64.b64decode(state['_current-profile']).decode() == catalog['2ac3']['Key'],
          'startup primary differs')
  for pid in ('2ac3', '30a1'):
    prefs = decode(catalog[pid]['Key'])
    require(prefs.get('CorpDNS') is True and prefs.get('OperatorUser') == 'joseph',
            'selected profile requires accept-dns and operator=joseph')
  return {key: selected[key] for key in ('primary', 'secondary', 'preferred')}


def replace_link(path, target):
  temp = path.with_name(path.name + '.multinet')
  require(not temp.exists() and not temp.is_symlink(), 'resolver temporary path already exists')
  temp.symlink_to(target)
  temp.replace(path)


def no_experiment_routes():
  for family in ('-4', '-6'):
    require(not re.search(r'lookup 5280\b', command('ip', family, 'rule')), 'multinet rule remains')
    require(not command('ip', family, 'route', 'show', 'table', '5280', check=False).strip(),
            'multinet routes remain')
  for tool in ('iptables-save', 'ip6tables-save'):
    rules = command(tool)
    require('tailscale-multi-profile' not in rules and 'tsmp-' not in rules, 'multinet firewall remains')


def dns_health(server):
  for tcp in ([], ['+tcp']):
    for name in ('rocket.rockhopper-bleak.ts.net', 'example.com'):
      answer = command('dig', '@' + server, name, '+time=3', '+tries=1', *tcp)
      require('status: NOERROR' in answer and re.search(r'ANSWER: [1-9]', answer), 'DNS health failed')


def recover():
  # Stop the startup writer first. Never start native daemons until the
  # experimental process and its kernel ownership are verified gone.
  ctl('stop', 'tailscale-multinet-start.service', DAEMON)
  require(active(DAEMON) in ('inactive', 'failed'), 'multinet daemon still running')
  no_experiment_routes()
  VERIFIED.unlink(missing_ok=True)
  CONFIRMED.unlink(missing_ok=True)
  if MARKER.exists():
    replace_link(Path('/etc/resolv.conf'), '/etc/static/resolv.conf')
    # directManager's base file must never become an immutable Nix target.
    backup = Path('/etc/resolv.pre-tailscale-backup.conf')
    if backup.is_symlink() and os.readlink(backup) == str(NM_DNS):
      backup.unlink()
    MARKER.unlink()
  for unit in NATIVE:
    ctl('start', unit if '.' in unit else unit + '.service')
  dns_health('127.0.0.2')
  VERIFIED.touch()
  ctl('stop', 'tailscale-multinet-deadline.timer')


def verify(expected):
  status = json.loads(cli('network', 'status'))
  require(status.get('primary') == expected['primary'] and status.get('preferred') == expected['preferred'],
          'profile ownership differs')
  require(sorted(p['profile']['ID'] for p in status.get('profiles', [])) == ['2ac3', '30a1']
          and all(p['state'] == 6 for p in status['profiles'])
          and not status.get('hostErrors') and not status.get('restoreErrors')
          and not status.get('overlaps'), 'selected profiles not healthy')
  require(selection() == expected, 'saved selection changed during startup')
  require('nameserver 127.0.0.3' in Path('/etc/resolv.conf').read_text(), 'multinet DNS not installed')
  require(Path('/etc/resolv.pre-tailscale-backup.conf').is_symlink()
          and Path('/etc/resolv.pre-tailscale-backup.conf').resolve() == NM_DNS, 'underlay backup differs')
  dns_health('127.0.0.3')
  for tcp in ([], ['+tcp']):
    answer = command('dig', '@127.0.0.3', 'agent01.mink-pangolin.ts.net', '+time=3', '+tries=1', *tcp)
    require('status: NOERROR' in answer and re.search(r'ANSWER: [1-9]', answer), 'work DNS health failed')
    require('status: NXDOMAIN' in command('dig', '@127.0.0.3', 'doubleclick.net', '+time=3', '+tries=1', *tcp),
            'home filtering health failed')
  for unit in GUARDS:
    require(active(unit if '.' in unit else unit + '.service') in ('inactive', 'failed'), 'competing native writer')


def wait_healthy(expected):
  deadline = time.monotonic() + 150
  while True:
    require(active(DAEMON) == 'active', 'multinet daemon stopped')
    try:
      verify(expected)
      return
    except (RuntimeError, subprocess.SubprocessError):
      if time.monotonic() >= deadline:
        raise
      time.sleep(3)


def stop_native():
  for unit in reversed(GUARDS):
    unit = unit if '.' in unit else unit + '.service'
    if command('systemctl', 'show', unit, '-p', 'LoadState', '--value').strip() != 'not-found':
      ctl('stop', unit)


def start():
  require(VERIFIED.exists() and not MARKER.exists(), 'native recovery not verified')
  expected = selection()
  require(NM_DNS.is_file(), 'no live DHCP DNS')
  servers = [ipaddress.ip_address(line.split()[1]) for line in NM_DNS.read_text().splitlines()
             if line.startswith('nameserver ')]
  require(servers and all(not (ip.is_loopback or ip.is_unspecified or ip.is_multicast)
                          and str(ip) not in ('100.100.100.100', 'fd7a:115c:a1e0::53')
                          for ip in servers), 'unsupported or recursive DHCP DNS')
  ctl('restart', 'tailscale-multinet-deadline.timer')
  require(active('tailscale-multinet-deadline.timer') == 'active', 'independent deadline not armed')
  MARKER.touch()
  VERIFIED.unlink()
  stop_native()
  require(not Path('/run/netns/work-tailnet').exists(), 'native namespace remains')
  replace_link(Path('/etc/resolv.pre-tailscale-backup.conf'), NM_DNS)
  temp = Path('/etc/resolv.conf.multinet')
  require(not temp.exists() and not temp.is_symlink(), 'resolver temporary path already exists')
  temp.write_text('# resolv.conf(5) file generated by tailscale\nnameserver 127.0.0.3\n')
  temp.chmod(0o644)
  temp.replace('/etc/resolv.conf')
  ctl('start', DAEMON)
  wait_healthy(expected)
  ctl('restart', DAEMON)
  wait_healthy(expected)
  CONFIRMED.touch()
  ctl('stop', 'tailscale-multinet-deadline.timer')


def prop(path, interface, name):
  return json.loads(command('busctl', '--system', '--json=short', 'get-property', NM, path, interface, name))['data']


def underlay():
  if not prop(ROOT, NM, 'ConnectivityCheckEnabled'):
    return '', 0
  connection = prop(ROOT, NM, 'PrimaryConnection')
  if connection == '/' or prop(connection, NM + '.Connection.Active', 'Type') not in ('802-11-wireless', '802-3-ethernet', 'gsm'):
    return '', 0
  states = []
  for device in prop(connection, NM + '.Connection.Active', 'Devices'):
    if prop(device, NM + '.Device', 'State') == 100:
      states += [prop(device, NM + '.Device', f'Ip{family}Connectivity') for family in (4, 6)]
  if prop(ROOT, NM, 'PrimaryConnection') != connection:
    return '', 0
  return connection, next((s for s in (4, 2, 3, 1) if s in states), 0)


class Settled:
  def __init__(self):
    self.key, self.since = None, 0

  def ready(self, key, now):
    if key is None or key != self.key:
      self.key, self.since = key, now
    return key is not None and now - self.since >= 20


def monitor():
  ctl('start', '--no-block', 'tailscale-multinet-recover.service')
  phase, gate = 'recovering', Settled()
  while True:
    connection, connectivity = underlay()
    if phase == 'recovering':
      if active('tailscale-multinet-recover.service') == 'failed':
        raise RuntimeError('native recovery failed; independent job continues')
      if VERIFIED.exists() and active('tailscale-multinet-recover.service') == 'inactive':
        phase, gate = 'native', Settled()
    elif phase == 'native':
      if gate.ready((connection, 'full') if connectivity == 4 else None, time.monotonic()):
        ctl('start', '--no-block', 'tailscale-multinet-start.service')
        phase = 'starting'
    elif phase == 'starting':
      require(active('tailscale-multinet-start.service') != 'failed', 'startup failed')
      if CONFIRMED.exists() and active('tailscale-multinet-start.service') == 'inactive':
        phase, gate = 'vpn', Settled()
    elif phase == 'vpn':
      require(active(DAEMON) == 'active', 'daemon failed')
      if gate.ready((connection, 'blocked') if connectivity in (1, 2, 3) else None, time.monotonic()):
        ctl('start', '--no-block', 'tailscale-multinet-recover.service')
        phase = 'recovering'
    time.sleep(3)


if __name__ == '__main__':
  os.umask(0o077)
  RUN.mkdir(mode=0o700, exist_ok=True)
  action = sys.argv[1]
  if action == 'monitor':
    monitor()
  else:
    if action == 'recover':
      ctl('stop', 'tailscale-multinet-start.service')
    with (RUN / 'transition.lock').open('w') as lock:
      fcntl.flock(lock, fcntl.LOCK_EX)
      {'start': start, 'recover': recover}[action]()
