"""Durable evidence fixtures; no production jobs, units or artifacts."""
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid

import job
import poll


class JobChecks(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.root = Path(self.temp.name)
    self.record = self.root / 'job.json'
    self.report = self.root / 'result.json'
    self.report.write_text(json.dumps({'jobId': 'fixture', 'total': 17, 'final': True}))
    verifier = self.root / 'verify.py'
    verifier.write_text('''import json,sys
from pathlib import Path
r=json.loads(Path(sys.argv[1]).read_text())
print(json.dumps({'completionValid': r.get('jobId')=='fixture' and
 type(r.get('total')) is int and r['total']==17 and r.get('final') is True}))
''')
    self.c = {'jobId': 'fixture', 'watchId': str(uuid.uuid4()), 'jobRecord': str(self.record),
              'jobCommand': [sys.executable, '-c', 'pass'],
              'resultCommand': [sys.executable, str(verifier), str(self.report)],
              'jobUnit': 'fixture.service', 'systemctl': '/synthetic/systemctl'}

  def execute(self):
    config = self.root / 'config.json'
    config.write_text(json.dumps(self.c))
    return subprocess.run([sys.executable, '-B', str(Path(job.__file__)), 'run', '--config', str(config)],
                          capture_output=True, text=True, timeout=5)

  def test_collected_success_preserves_identity_exit_and_validated_results(self):
    self.assertEqual(self.execute().returncode, 0)
    with patch.object(job, 'command', side_effect=AssertionError('Collected unit must not be queried')):
      result = job.status(self.c)
    self.assertEqual(result, {'jobId': 'fixture', 'state': 'succeeded', 'exitCode': 0, 'completionValid': True})
    record = json.loads(self.record.read_text())
    self.assertEqual(record['identity']['watchId'], self.c['watchId'])
    self.assertTrue(record['startedAtUtc'])
    self.assertTrue(record['finishedAtUtc'])
    self.assertEqual(self.record.stat().st_mode & 0o777, 0o600)

  def test_collected_failure_keeps_actual_exit_even_with_successful_result_file(self):
    self.c['jobCommand'] = [sys.executable, '-c', 'raise SystemExit(7)']
    self.assertEqual(self.execute().returncode, 7)
    with patch.object(job, 'command', side_effect=AssertionError('No retained unit')):
      result = job.status(self.c)
    self.assertEqual((result['state'], result['exitCode'], result['completionValid']), ('failed', 7, False))

  def test_missing_incomplete_wrong_identity_results_cannot_establish_success(self):
    for report in [{}, {'jobId': 'fixture', 'total': 16, 'final': True},
                   {'jobId': 'other', 'total': 17, 'final': True},
                   {'jobId': 'fixture', 'total': 17}]:
      self.record.unlink(missing_ok=True)
      self.report.write_text(json.dumps(report))
      self.assertEqual(self.execute().returncode, 0)
      self.assertFalse(job.status(self.c)['completionValid'])
    self.record.unlink()
    self.report.unlink()
    self.assertEqual(self.execute().returncode, 0)
    result = job.status(self.c)
    self.assertEqual(result['exitCode'], 0)
    self.assertFalse(result['completionValid'])
    config = {**self.c, 'projectId': 'project', 'threadId': 'thread', 'scheduledTaskId': 'schedule'}
    self.assertEqual(poll.event_from_status(config, result)['reason'], 'invalid_completion')

  def test_missing_partial_completion_and_wrong_execution_records_are_observation_errors(self):
    with self.assertRaises(FileNotFoundError):
      job.status(self.c)
    self.assertEqual(self.execute().returncode, 0)
    record = json.loads(self.record.read_text())
    for field in ['exitCode', 'completionValid', 'finishedAtUtc']:
      self.record.write_text(json.dumps({k: v for k, v in record.items() if k != field}))
      with self.assertRaises((KeyError, ValueError)):
        job.status(self.c)
    self.record.write_text(json.dumps(record))
    for change in [{'watchId': str(uuid.uuid4())}, {'jobId': 'another'},
                   {'jobCommand': [sys.executable, '-c', 'print(1)']},
                   {'resultCommand': [sys.executable, '-c', 'print(1)']}]:
      with self.assertRaises(ValueError):
        job.status({**self.c, **change})
    self.record.write_text('{')
    with self.assertRaises(ValueError):
      job.status(self.c)

  def test_running_checks_invocation_and_does_not_wait_forever_on_active_exited(self):
    self.record.write_text(json.dumps({'identity': job.identity(self.c), 'phase': 'running', 'invocationId': 'exact'}))
    for state, valid in [('LoadState=loaded\nActiveState=active\nSubState=running\nInvocationID=exact', True),
                         ('LoadState=not-found\nActiveState=inactive\nInvocationID=', False),
                         ('LoadState=loaded\nActiveState=active\nSubState=exited\nInvocationID=exact', False),
                         ('LoadState=loaded\nActiveState=active\nSubState=running\nInvocationID=other', False)]:
      with patch.object(job, 'command', return_value=state.encode()):
        if valid:
          self.assertEqual(job.status(self.c)['state'], 'running')
        else:
          with self.assertRaises(ValueError):
            job.status(self.c)

  def test_wrapper_refuses_to_run_same_execution_again(self):
    self.assertEqual(self.execute().returncode, 0)
    before = self.record.read_bytes()
    self.assertNotEqual(self.execute().returncode, 0)
    self.assertEqual(self.record.read_bytes(), before)

  def test_termination_records_real_child_signal(self):
    self.c['jobCommand'] = [sys.executable, '-c',
                            'from pathlib import Path; import time; Path(' + repr(str(self.root / 'ready')) +
                            ').touch(); time.sleep(30)']
    config = self.root / 'config.json'
    config.write_text(json.dumps(self.c))
    process = subprocess.Popen([sys.executable, '-B', str(Path(job.__file__)), 'run', '--config', str(config)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    def cleanup():
      if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
      process.wait(timeout=5)
    self.addCleanup(cleanup)
    deadline = time.monotonic() + 5
    while not (self.root / 'ready').exists():
      if time.monotonic() > deadline:
        self.fail('Child did not start')
      time.sleep(.01)
    process.terminate()
    self.assertEqual(process.wait(timeout=5), 128 + signal.SIGTERM)
    self.assertEqual(job.status(self.c)['exitCode'], -signal.SIGTERM)

  def test_missing_record_wakes_owner_after_bounded_observation_failures(self):
    config = {**self.c, 'projectId': 'project', 'threadId': 'thread', 'scheduledTaskId': 'schedule',
              'stateDirectory': str(self.root / 'watch'), 'observationFailureLimit': 3}
    events = []
    with redirect_stdout(io.StringIO()):
      for attempt in range(2):
        with self.assertRaises(FileNotFoundError):
          poll.check_once(config, fetch_status=lambda _: job.status(self.c))
      poll.check_once(config, fetch_status=lambda _: job.status(self.c),
                      deliver=lambda _, e: events.append(e) or 'accepted', stop_timer=lambda _: None)
    self.assertEqual(events[0]['event'], 'observation_failed')
    self.assertEqual(events[0]['status'], 'unknown')

  @unittest.skipUnless(os.environ.get('T3_NOTIFY_SYSTEMD_TEST') == '1', 'explicit disposable systemd smoke')
  def test_real_collected_success_and_failure_still_have_completion_records(self):
    ctl = shutil.which('systemctl')
    for code in [0, 7]:
      with self.subTest(code=code):
        self.record.unlink(missing_ok=True)
        name = 't3-job-fixture-' + str(uuid.uuid4()) + '.service'
        self.c['jobUnit'] = name
        self.c['systemctl'] = ctl
        self.c['jobCommand'] = [sys.executable, '-c', f'raise SystemExit({code})']
        config = self.root / 'config.json'
        config.write_text(json.dumps(self.c))
        def cleanup(name=name):
          subprocess.run([ctl, '--user', 'stop', name], capture_output=True, timeout=5)
          subprocess.run([ctl, '--user', 'reset-failed', name], capture_output=True, timeout=5)
        self.addCleanup(cleanup)
        result = subprocess.run(['systemd-run', '--user', '--wait', '--unit=' + name,
                                 '--property=Type=exec', '--property=RuntimeMaxSec=10',
                                 sys.executable, '-B', str(Path(job.__file__)), 'run', '--config', str(config)],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        self.assertTrue(json.loads(self.record.read_text())['invocationId'])
        cleanup()
        loaded = subprocess.run([ctl, '--user', 'show', name, '--property=LoadState', '--value'],
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(loaded.stdout.strip(), 'not-found')
        self.assertEqual(job.status(self.c)['exitCode'], code)


if __name__ == '__main__':
  unittest.main()
