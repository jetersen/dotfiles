"""Run the event worker with fake control endpoints, without live services."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class FetchRetry(unittest.TestCase):
    def test_busy_notification_waits_for_failed_evaluation(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            mock = work / 'control'
            mock.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STATE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
s['calls'].append(a)
if 'is-active' in a:
    code = 0 if s['active'] else 1
elif a == ['status', '--json']:
    print(json.dumps(s['status']))
    code = 0
elif 'try-restart' in a:
    s['status']['builder']['generation']['eval_status'] = 'success'
    code = 0
else:
    code = 0
p.write_text(json.dumps(s))
sys.exit(code)
''')
            mock.chmod(0o755)
            script = (ROOT / 'nixos/gitops/fetch.sh').read_text()
            for key, value in {'systemctl': str(mock), 'comin': str(mock),
                               'timeout': shutil.which('timeout'),
                               'jq': shutil.which('jq'), 'sleep': shutil.which('true')}.items():
                script = script.replace(f'@{key}@', value)
            state = work / 'state'
            data = {'active': True, 'calls': [], 'status': {
                'is_suspended': False, 'fetcher': {'is_fetching': False},
                'deployer': {'is_deploying': False}, 'builder': {
                    'is_evaluating': True, 'is_building': False,
                    'generation': {'eval_status': 'running', 'build_status': ''}}}}
            def execute():
                state.write_text(json.dumps(data))
                subprocess.run(['bash', '-c', script], check=True,
                               env={**os.environ, 'MOCK_STATE': str(state)})
                return json.loads(state.read_text())
            data = execute()
            self.assertIn(['--no-block', 'restart', 'comin-fetch-retry.timer'], data['calls'])
            self.assertNotIn(['fetch'], data['calls'])
            self.assertNotIn(['try-restart', 'comin.service'], data['calls'])
            data['calls'] = []
            data['status']['builder'].update(is_evaluating=False)
            data['status']['builder']['generation']['eval_status'] = 'failed'
            data = execute()
            self.assertIn(['try-restart', 'comin.service'], data['calls'])
            self.assertIn(['fetch'], data['calls'])
            self.assertNotIn(['--no-block', 'restart', 'comin-fetch-retry.timer'], data['calls'])
            for active, suspended in ((False, False), (True, True)):
                data['active'] = active
                data['status']['is_suspended'] = suspended
                data['calls'] = []
                data = execute()
                self.assertFalse(any('restart' in c or 'try-restart' in c or c == ['fetch']
                                     for c in data['calls']))

    def test_timer_has_no_unsolicited_schedule(self):
        module = (ROOT / 'nixos/modules/gitops.nix').read_text()
        timer = module.split('systemd.timers.comin-fetch-retry = {', 1)[1].split(
            'systemd.services.comin-fetch-retry', 1)[0]
        self.assertIn('OnActiveSec = "120s"', timer)
        self.assertIn('unitConfig.StartLimitIntervalSec = 0', timer)
        self.assertIn('TimeoutStartSec = 90', module)
        self.assertNotIn('ExecStartPost', module)  # Internal retry cannot request another retry.
        for setting in ('wantedBy', 'OnCalendar', 'OnUnitActiveSec', 'OnUnitInactiveSec', 'Persistent'):
            self.assertNotIn(setting, timer)


if __name__ == '__main__':
    unittest.main()
