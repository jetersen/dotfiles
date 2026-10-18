"""Exercise deployment notifications without connecting to either host."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class NotifyHosts(unittest.TestCase):
    def test_both_hosts_receive_pinned_notifications_even_if_framework_is_offline(self):
        for framework_fails in (False, True):
            with self.subTest(framework_fails=framework_fails), tempfile.TemporaryDirectory() as tmp:
                work = Path(tmp)
                ssh = work / 'ssh'
                ssh.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
known_hosts = next(a.split('=', 1)[1] for a in args if a.startswith('UserKnownHostsFile='))
with open(os.environ['CALLS'], 'a') as calls:
    calls.write(json.dumps({'args': args, 'known_hosts': Path(known_hosts).read_text()}) + '\\n')
sys.exit(1 if os.environ['FRAMEWORK_FAILS'] == '1' and args[-2] == 'comin-notify@framework.test' else 0)
''')
                ssh.chmod(0o755)
                calls = work / 'calls'
                subprocess.run(['bash', 'nixos/ci/notify-hosts.sh'], cwd=ROOT, check=True,
                               capture_output=True, text=True, env={
                                   **os.environ, 'PATH': str(work) + os.pathsep + os.environ['PATH'],
                                   'NOTIFY_KEY': 'fixture-private-key', 'RUNNER_TEMP': tmp,
                                   'FRAMEWORK_HOST': 'framework.test', 'ROCKET_HOST': 'rocket.test',
                                   'CALLS': str(calls), 'FRAMEWORK_FAILS': str(int(framework_fails)),
                               })
                notifications = [json.loads(line) for line in calls.read_text().splitlines()]
                self.assertEqual(len(notifications), 2)
                for machine, notification in zip(('framework', 'rocket'), notifications):
                    args = notification['args']
                    self.assertEqual(args[-2:], [f'comin-notify@{machine}.test', 'comin fetch'])
                    self.assertIn('StrictHostKeyChecking=yes', args)
                    self.assertIn(f'HostKeyAlias={machine}', args)
                    key_type, public_key, *_ = (ROOT / f'nixos/keys/{machine}-host.pub').read_text().split()
                    self.assertEqual(notification['known_hosts'], f'{machine} {key_type} {public_key}\n')
                self.assertFalse((work / 'nixos-notify-key').exists())
                self.assertFalse((work / 'nixos-notify-known-hosts').exists())


if __name__ == '__main__':
    unittest.main()
