"""Disposable sources/endpoints only. Set T3_NOTIFY_SYSTEMD_TEST=1 for user timer smoke."""
from contextlib import closing, redirect_stdout
import fcntl
import datetime
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
import select
import shutil
from pathlib import Path
import socket
import ssl
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import Mock, patch
import uuid

import local_endpoint
import poll

HERE = Path(__file__).resolve().parent
KEY = 'synthetic-signing-key-for-disposable-tests'


class Checks(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.root = Path(self.temp.name)
    self.state = self.root / 'state'
    self.source = self.root / 'result.json'
    self.source.write_text(json.dumps({'jobId': 'fixture-job', 'state': 'running'}))
    # Example job adapter: verifies authoritative identity and expected result total.
    self.adapter = self.root / 'adapter.py'
    self.adapter.write_text('''import json, sys
from pathlib import Path
raw = json.loads(Path(sys.argv[1]).read_text())
print(json.dumps({**raw, 'completionValid': raw.get('total') == 17}))
''')
    self.endpoint = self.root / 'endpoint.py'
    self.endpoint.write_text('import sys\nfrom pathlib import Path\nprint(Path(sys.argv[1]).read_text())\n')
    self.url_file = self.root / 'url'
    self.config_path = self.root / 'config.json'
    self.c = {'jobId': 'fixture-job', 'watchId': str(uuid.uuid4()), 'scheduledTaskId': 'fixture-task',
              'threadId': 'fixture-thread', 'projectId': 'fixture-project',
              'stateDirectory': str(self.state),
              'adapterCommand': [sys.executable, str(self.adapter), str(self.source)],
              'endpointCommand': [sys.executable, str(self.endpoint), str(self.url_file)],
              'systemctl': shutil.which('systemctl') or sys.executable,
              'httpTimeout': .2, 'adapterTimeout': .5, 'endpointTimeout': .5}
    self.config_path.write_text(json.dumps(self.c))
    self.c = poll.load_config(self.config_path)
    self.sent = []
    self.stops = []
    self.output = io.StringIO()
    self.redirect = redirect_stdout(self.output)
    self.redirect.__enter__()
    self.addCleanup(self.redirect.__exit__, None, None, None)

  def terminal(self, **changes):
    return {'jobId': self.c['jobId'], 'state': 'succeeded', 'exitCode': 0,
            'completionValid': True, **changes}

  def tick(self, status=None, deliver=None, stop=None, fetch=None):
    return poll.check_once(self.c, fetch_status=fetch or (lambda _: status or self.terminal()),
                           deliver=deliver or (lambda _, e: self.sent.append(e) or 'accepted'),
                           stop_timer=stop or (lambda _: self.stops.append(True)))

  def credentials(self, url, key=KEY):
    self.url_file.write_text(json.dumps({'url': url, 'signingKey': key}))

  def serve(self, responses, tls=False):
    records = []
    class Handler(BaseHTTPRequestHandler):
      def log_message(self, *args):
        pass
      def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        signature = 'sha256=' + hmac.new(KEY.encode(), body, hashlib.sha256).hexdigest()
        records.append((self.path, json.loads(body), body))
        if not hmac.compare_digest(self.headers.get('x-t3-notify-signature', ''), signature):
          self.send_response(401)
          self.end_headers()
          return
        response = responses.pop(0) if len(responses) > 1 else responses[0]
        if response is None:
          self.connection.shutdown(socket.SHUT_RDWR)
          self.connection.close()
          return
        code, outcome = response
        self.send_response(code)
        self.send_header('x-t3-hook-outcome', outcome)
        if code == 302:
          self.send_header('Location', '/redirected-secret')
        self.end_headers()
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    if tls:
      cert, key = self.root / 'cert.pem', self.root / 'key.pem'
      subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                      '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
                      '-keyout', str(key), '-out', str(cert)], capture_output=True, check=True, timeout=10)
      context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
      context.load_cert_chain(cert, key)
      server.socket = context.wrap_socket(server.socket, server_side=True)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    def close():
      server.shutdown()
      server.server_close()
      thread.join()
    self.addCleanup(close)
    if tls:
      self.c['httpsOrigin'] = f'https://localhost:{server.server_port}'
      self.credentials(self.c['httpsOrigin'] + '/fixture-secret-capability')
    else:
      self.credentials(f'http://127.0.0.1:{server.server_port}/fixture-secret-capability')
    return records

  def test_active_is_quiet_and_checks_exact_identity(self):
    self.assertEqual(self.tick({'jobId': 'fixture-job', 'state': 'running'}), 'running')
    self.assertEqual(self.sent, [])
    self.assertEqual(self.stops, [])
    self.assertFalse((self.state / 'pending-terminal.json').exists())
    self.assertEqual(json.loads((self.state / 'last-check.json').read_text())['state'], 'running')
    with self.assertRaises(ValueError):
      self.tick({'jobId': 'other', 'state': 'running'})

  def test_readable_identities_are_preserved_and_compared_exactly(self):
    self.c['jobId'] = 'Build #12 / Linux – æøå'
    self.config_path.write_text(json.dumps(self.c))
    self.c = poll.load_config(self.config_path)
    self.assertEqual(self.tick(), 'notified')
    self.assertEqual(self.sent[0]['jobId'], self.c['jobId'])
    with self.assertRaises(ValueError):
      poll.event_from_status(self.c, self.terminal(jobId='Build #12 / Linux'))

  def test_command_diagnostics_identify_stage_without_secret_text(self):
    with patch.object(poll, 'command', side_effect=RuntimeError(KEY)):
      for call, expected in [(poll.fetch, poll.AdapterCommandError),
                             (poll.resolve_credentials, poll.EndpointCommandError)]:
        with self.assertRaises(expected) as error:
          call(self.c)
        self.assertNotIn(KEY, str(error.exception))
    self.serve([(503, 'error')])
    self.source.write_text(json.dumps({'jobId':self.c['jobId'], 'state':'failed'}))
    self.config_path.write_text(json.dumps(self.c))
    self.assertEqual(poll.main(['tick','--config',str(self.config_path)]), 1)
    logged = json.loads(self.output.getvalue().splitlines()[-1])
    self.assertEqual(logged['httpStatus'], 503)
    self.assertNotIn(KEY, self.output.getvalue())
    self.assertNotIn('fixture-secret-capability', self.output.getvalue())

  def test_success_delivers_once_then_only_stops(self):
    self.assertEqual(self.tick(), 'notified')
    def forbidden(*args):
      self.fail('Repeated status lookup or delivery')
    self.assertEqual(self.tick(fetch=forbidden, deliver=forbidden), 'already_notified')
    self.assertEqual(len(self.sent), 1)
    self.assertEqual(len(self.stops), 2)
    self.assertFalse(json.loads((self.state / 'notified.json').read_text())['dispatchVerified'])
    self.assertIn('webhook_accepted', self.output.getvalue())
    self.assertNotIn('thread_notified', self.output.getvalue())

  def test_all_terminal_failures(self):
    for state in ['failed', 'cancelled', 'timed_out']:
      event = poll.event_from_status(self.c, self.terminal(state=state, completionValid=False))
      self.assertEqual(event['status'], state)

  def test_incomplete_success_becomes_failure(self):
    for changes in [{'completionValid': False}, {'completionValid': 1}, {'exitCode': 1},
                    {'exitCode': None}, {'exitCode': False}, {'exitCode': '0'}]:
      event = poll.event_from_status(self.c, self.terminal(**changes))
      self.assertEqual((event['status'], event['reason']), ('failed', 'invalid_completion'))
    event = poll.event_from_status(self.c, {'jobId': 'fixture-job', 'state': 'succeeded'})
    self.assertEqual(event['status'], 'failed')

  def test_malformed_and_unknown_results_do_not_notify(self):
    for status in [[], {}, {'jobId': 'other', 'state': 'succeeded'}, self.terminal(state='unknown')]:
      with self.assertRaises(ValueError):
        self.tick(status=status, fetch=lambda _, s=status: s)
    self.source.write_text('not JSON')
    with self.assertRaises(RuntimeError):
      poll.fetch(self.c)
    self.assertEqual(self.sent, [])

  def test_adapter_rejects_wrong_total_through_real_http(self):
    records = self.serve([(202, 'accepted')])
    self.source.write_text(json.dumps({'jobId': 'fixture-job', 'state': 'succeeded', 'exitCode': 0, 'total': 16}))
    poll.check_once(self.c, stop_timer=lambda _: None)
    self.assertEqual(records[0][1]['status'], 'failed')
    self.assertNotIn('total', records[0][1])

  def test_pending_survives_http_failure_and_resumes_without_lookup(self):
    records = self.serve([(503, 'error'), (202, 'accepted')])
    with self.assertRaises(Exception):
      self.tick(deliver=poll.post)
    pending = (self.state / 'pending-terminal.json').read_bytes()
    self.assertFalse((self.state / 'notified.json').exists())
    self.tick(deliver=poll.post, fetch=lambda _: self.fail('Pending event must be reused'))
    self.assertEqual(records[0][1], records[1][1])
    self.assertEqual(records[0][2], records[1][2])
    self.assertEqual((self.state / 'pending-terminal.json').read_bytes(), pending)

  def test_lost_ack_retries_same_event_and_accepts_duplicate(self):
    records = self.serve([None, (202, 'duplicate')])
    with self.assertRaises(Exception):
      self.tick(deliver=poll.post)
    self.tick(deliver=poll.post, fetch=lambda _: self.fail('Must not refetch'))
    self.assertEqual(records[0][1], records[1][1])
    self.assertEqual(records[0][2], records[1][2])
    self.assertEqual(json.loads((self.state / 'notified.json').read_text())['outcome'], 'duplicate')

  def test_interruption_after_delivery_before_receipt(self):
    records = self.serve([(202, 'accepted'), (202, 'duplicate')])
    real_atomic = poll.atomic
    def interrupt(path, value):
      if path.name == 'notified.json':
        raise OSError('Simulated interruption')
      real_atomic(path, value)
    with patch.object(poll, 'atomic', side_effect=interrupt), self.assertRaises(OSError):
      self.tick(deliver=poll.post)
    self.tick(deliver=poll.post)
    self.assertEqual(records[0][1]['eventId'], records[1][1]['eventId'])
    self.assertEqual(records[0][2], records[1][2])

  def test_old_pending_stops_without_replaying_after_retention(self):
    old = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=6, seconds=1)).isoformat()
    with patch.object(poll, 'now', return_value=old):
      self.assertEqual(self.tick(deliver=lambda *_: self.fail('Expired delivery')), 'expired')
    self.assertFalse((self.state / 'notified.json').exists())
    self.assertTrue((self.state / 'pending-terminal.json').exists())
    self.assertEqual(self.stops, [True])

  def test_only_positive_acknowledgements_complete(self):
    for code, outcome in [(200, 'accepted'), (202, 'filtered'), (202, 'coalesced'),
                          (202, 'dispatch_failed'), (409, 'disabled')]:
      with self.subTest(code=code, outcome=outcome):
        self.serve([(code, outcome)])
        with self.assertRaises(Exception):
          self.tick(deliver=poll.post)
        self.assertFalse((self.state / 'notified.json').exists())
    self.assertEqual(self.stops, [])

  def test_redirects_and_proxies_are_disabled(self):
    records = self.serve([(302, 'redirect')])
    with patch.dict(os.environ, {'http_proxy': 'http://127.0.0.1:1', 'HTTP_PROXY': 'http://127.0.0.1:1',
                                 'NO_PROXY': '', 'no_proxy': ''}), self.assertRaises(Exception):
      self.tick(deliver=poll.post)
    self.assertEqual(len(records), 1)
    self.assertEqual(records[0][0], '/fixture-secret-capability')

  def test_loopback_validation(self):
    for url in ['https://127.0.0.1:123/hook', 'http://localhost:123/hook',
                'http://example.com:123/hook', 'http://127.0.0.1:123/hook?q=secret',
                'http://user@127.0.0.1:123/hook', 'http://127.0.0.1:123/hook#secret']:
      with self.assertRaises(ValueError):
        poll.loopback_url(url)

  def test_signatures_are_required_and_checked_over_actual_request_bytes(self):
    records = self.serve([(202, 'accepted')])
    url = json.loads(self.url_file.read_text())['url']
    self.credentials(url, 'wrong-synthetic-key-long-enough-for-test')
    with self.assertRaises(Exception):
      self.tick(deliver=poll.post)
    self.assertFalse((self.state / 'notified.json').exists())
    self.credentials(url)
    self.tick(deliver=poll.post)
    self.assertEqual(records[0][1], records[1][1])
    self.assertEqual(records[0][2], records[1][2])
    self.assertNotIn(KEY, self.output.getvalue())
    self.assertNotIn(KEY, (self.state / 'notified.json').read_text())

  def test_missing_or_weak_signing_key_never_sends(self):
    records = self.serve([(202, 'accepted')])
    url = json.loads(self.url_file.read_text())['url']
    for credentials in [{'url': url}, {'url': url, 'signingKey': 'short'},
                        {'url': url, 'signingKey': 42}]:
      self.url_file.write_text(json.dumps(credentials))
      with self.assertRaises((KeyError, ValueError)):
        self.tick(deliver=poll.post)
    self.assertEqual(records, [])

  def test_preflight_is_secret_safe_and_does_not_send(self):
    records = self.serve([(202, 'accepted')])
    self.config_path.write_text(json.dumps(self.c))
    result = subprocess.run([sys.executable, str(HERE / 'poll.py'), 'preflight', '--config', str(self.config_path)],
                            capture_output=True, text=True, timeout=5)
    self.assertEqual(result.returncode, 0, result.stdout)
    self.assertEqual(records, [])
    self.assertIn('credential_preflight_ok', result.stdout)
    self.assertNotIn('fixture-secret', result.stdout + result.stderr)
    self.assertNotIn(KEY, result.stdout + result.stderr)
    self.assertFalse(self.state.exists())

  def test_https_requires_one_exact_explicit_origin(self):
    c = {**self.c, 'httpsOrigin': 'https://host.example.ts.net'}
    self.assertEqual(poll.endpoint_url(c, 'https://host.example.ts.net/hook'), 'https://host.example.ts.net/hook')
    for url in ['https://other.example.ts.net/hook', 'https://host.example.ts.net.evil/hook',
                'http://host.example.ts.net/hook', 'http://127.0.0.1:123/hook',
                'https://host.example.ts.net:444/hook', 'https://user@host.example.ts.net/hook',
                'https://host.example.ts.net/hook?q=secret', 'https://host.example.ts.net/hook#secret']:
      with self.assertRaises(ValueError):
        poll.endpoint_url(c, url)
    with self.assertRaises(ValueError):
      poll.endpoint_url(self.c, 'https://host.example.ts.net/hook')
    for origin in ['http://host.example.ts.net', 'https://host.example.ts.net/',
                   'https://user@host.example.ts.net', 'https://host.example.ts.net?secret',
                   'https://host.example.ts.net#secret', 'https://host.example.ts.net:0']:
      with self.assertRaises(ValueError):
        poll.https_origin(origin)

  def test_remote_http_is_rejected_without_a_request_or_loopback_fallback(self):
    records = self.serve([(202, 'accepted')])
    self.credentials('http://100.100.1.2:12345/fixture-secret-capability')
    with self.assertRaises(ValueError):
      self.tick(deliver=poll.post)
    for extra in [{}, {'httpsOrigin': 'https://host.example.ts.net'}]:
      c = {**self.c, **extra, 'tailnetHttp': {'origin': 'http://100.100.1.2:12345'}}
      self.config_path.write_text(json.dumps(c))
      with self.assertRaises(ValueError):
        poll.load_config(self.config_path)
      with self.assertRaises(ValueError):
        poll.endpoint_url(c, 'http://127.0.0.1:12345/hook')
    self.assertEqual(records, [])
    self.assertFalse((self.state / 'notified.json').exists())

  @unittest.skipUnless(shutil.which('openssl'), 'TLS fixture needs openssl')
  def test_https_verifies_certificates_signs_and_retries_identical_payload(self):
    records = self.serve([(503, 'error'), (202, 'duplicate')], tls=True)
    with self.assertRaises(Exception):
      self.tick(deliver=poll.post)
    self.assertEqual(records, [])
    # Nix's OpenSSL honors NIX_SSL_CERT_FILE ahead of the standard variable.
    with patch.dict(os.environ, {'SSL_CERT_FILE': str(self.root / 'cert.pem'),
                                 'NIX_SSL_CERT_FILE': str(self.root / 'cert.pem'),
                                 'HTTPS_PROXY': 'http://127.0.0.1:1',
                                 'https_proxy': 'http://127.0.0.1:1',
                                 'NO_PROXY': '', 'no_proxy': ''}):
      with self.assertRaises(Exception):
        self.tick(deliver=poll.post)
      self.assertFalse((self.state / 'notified.json').exists())
      self.tick(deliver=poll.post)
    self.assertEqual(records[0][1]['status'], 'succeeded')
    self.assertEqual(records[0][2], records[1][2])
    self.assertEqual(json.loads((self.state / 'notified.json').read_text())['outcome'], 'duplicate')

  @unittest.skipUnless(shutil.which('openssl'), 'TLS fixture needs openssl')
  def test_https_does_not_skip_hostname_verification(self):
    records = self.serve([(202, 'accepted')], tls=True)
    origin = self.c['httpsOrigin'].replace('localhost', '127.0.0.1')
    self.c['httpsOrigin'] = origin
    self.credentials(origin + '/fixture-secret-capability')
    with patch.dict(os.environ, {'SSL_CERT_FILE': str(self.root / 'cert.pem'),
                                 'NIX_SSL_CERT_FILE': str(self.root / 'cert.pem')}), self.assertRaises(Exception):
      self.tick(deliver=poll.post)
    self.assertEqual(records, [])

  def test_concurrent_process_tick_skips_locked_watch(self):
    self.state.mkdir(mode=0o700)
    with (self.state / 'poll.lock').open('a') as lock:
      fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
      result = subprocess.run([sys.executable, str(HERE / 'poll.py'), 'tick', '--config', str(self.config_path)],
                              capture_output=True, timeout=2)
    self.assertEqual(result.returncode, 0)
    self.assertFalse((self.state / 'last-check.json').exists())

  def test_state_identity_prevents_reuse_and_stopping_other_watch(self):
    self.tick()
    for field in ['watchId', 'jobId', 'scheduledTaskId', 'threadId', 'projectId']:
      c = {**self.c, field: 'other'}
      with self.assertRaises(ValueError):
        poll.check_once(c, stop_timer=lambda _: self.fail('Wrong owner must not stop'))
    event_path = self.state / 'pending-terminal.json'
    event = json.loads(event_path.read_text())
    event['status'] = 'failed'
    event_path.write_text(json.dumps(event))
    with self.assertRaises(ValueError):
      self.tick(stop=lambda _: self.fail('Corrupt event must not stop'))

  def test_stop_failure_retries_stop_without_redelivery(self):
    def fail(_):
      raise OSError('stop failed')
    with self.assertRaises(OSError):
      self.tick(stop=fail)
    self.assertTrue((self.state / 'notified.json').exists())
    self.tick(fetch=lambda _: self.fail('No lookup'), deliver=lambda *_: self.fail('No redelivery'))
    self.assertEqual(len(self.sent), 1)

  def test_atomic_interruption_preserves_previous_json(self):
    path = self.root / 'atomic.json'
    poll.atomic(path, {'v': 1})
    with patch.object(poll.os, 'replace', side_effect=OSError('interrupted')), self.assertRaises(OSError):
      poll.atomic(path, {'v': 2})
    self.assertEqual(json.loads(path.read_text()), {'v': 1})
    self.assertEqual(list(self.root.glob('atomic.json.*')), [])

  def test_commands_have_wall_time_output_limits_and_group_cleanup(self):
    start = time.monotonic()
    with self.assertRaises(TimeoutError):
      poll.command([sys.executable, '-c', 'import time; time.sleep(10)'], .05)
    self.assertLess(time.monotonic() - start, 1)
    with self.assertRaises(ValueError):
      poll.command([sys.executable, '-c', 'print("x"*70000)'], 1)
    with self.assertRaises(RuntimeError):
      poll.command([sys.executable, '-c', 'raise SystemExit(1)'], 1)
    # A descendant holding stdout open must not escape the parent deadline.
    with self.assertRaises(TimeoutError):
      poll.command([sys.executable, '-c', 'import subprocess; subprocess.Popen(["sleep", "10"])'], .05)

  def test_http_wait_is_bounded(self):
    with socket.socket() as server:
      server.bind(('127.0.0.1', 0))
      server.listen()
      self.credentials(f'http://127.0.0.1:{server.getsockname()[1]}/secret')
      start = time.monotonic()
      with self.assertRaises(TimeoutError):
        self.tick(deliver=poll.post)
      self.assertLess(time.monotonic() - start, 1)

  def test_logs_and_payload_are_secret_safe(self):
    self.tick(self.terminal(stdout='secret', url='secret', summary={'token': 'secret'}))
    self.assertNotIn('secret', json.dumps(self.sent))
    # CLI error path must not stringify an HTTP error containing a capability URL.
    self.config_path.write_text(json.dumps(self.c))
    with patch.object(poll, 'check_once', side_effect=OSError('http://secret-token')):
      self.assertEqual(poll.main(['tick', '--config', str(self.config_path)]), 1)
    self.assertNotIn('secret', self.output.getvalue())
    self.assertIn('OSError', self.output.getvalue())

  def test_stop_checks_ownership_before_systemctl_stop(self):
    commands = []
    def fake(argv, timeout):
      commands.append(argv)
      return b'LoadState=loaded\nTransient=no\nDescription=unrelated\nUnit=other.service\n'
    with patch.object(poll, 'command', side_effect=fake), self.assertRaises(ValueError):
      poll.stop(self.c)
    self.assertEqual(len(commands), 1)

  def test_private_state_permissions(self):
    self.state.mkdir(mode=0o700)
    self.state.chmod(0o755)
    with self.assertRaises(ValueError):
      self.tick()

  def database_config(self):
    path = self.root / 'app.sqlite'
    schedule = {'type': 'webhook', 'signature': dict(poll.SIGNATURE),
                'dedupe': {'replayKey': '{{body.eventId}}'},
                'filters': [{'path': 'body.' + k, 'op': 'equals', 'value': self.c[k]}
                            for k in ('jobId', 'watchId')] +
                           [{'path': 'body.event', 'op': 'equals', 'value': 'job_terminal'}]}
    with closing(sqlite3.connect(path)) as db, db:
      db.execute('CREATE TABLE scheduled_tasks (task_id TEXT, webhook_token TEXT, enabled INTEGER, '
                 'project_id TEXT, thread_id TEXT, schedule_json TEXT, webhook_secret TEXT)')
      db.execute('INSERT INTO scheduled_tasks VALUES (?,?,?,?,?,?,?)',
                 ('fixture-task', 'synthetic-secret-token', 1, 'fixture-project', 'fixture-thread', json.dumps(schedule), KEY))
      db.execute('INSERT INTO scheduled_tasks VALUES (?,?,?,?,?,?,?)',
                 ('unrelated', 'unrelated-secret', 1, 'other', 'other', '{}', 'unrelated-key'))
    return {**self.c, 't3Compatibility': {'origin': 'http://127.0.0.1:12345', 'database': str(path),
                                         'runtimePid': os.getpid(),
                                         'runtimeIdentity': local_endpoint.runtime_identity(os.getpid())}}

  def test_compat_resolver_exact_binding_readonly_and_runtime(self):
    c = self.database_config()
    before = Path(c['t3Compatibility']['database']).read_bytes()
    self.assertTrue(local_endpoint.resolve(c)['url'].endswith('/fixture-task/synthetic-secret-token'))
    self.assertEqual(local_endpoint.resolve(c)['signingKey'], KEY)
    self.assertEqual(Path(c['t3Compatibility']['database']).read_bytes(), before)
    self.assertNotIn('synthetic-secret-token', json.dumps(c))
    for field in ['scheduledTaskId', 'projectId', 'threadId', 'jobId', 'watchId']:
      with self.assertRaises(ValueError):
        local_endpoint.resolve({**c, field: 'absent'})

  def test_compat_refuses_disabled_or_wrong_schedule(self):
    c = self.database_config()
    path = c['t3Compatibility']['database']
    with closing(sqlite3.connect(path)) as db, db:
      db.execute('UPDATE scheduled_tasks SET enabled=0 WHERE task_id=?', ('fixture-task',))
    with self.assertRaises(ValueError):
      local_endpoint.resolve(c)
    with closing(sqlite3.connect(path)) as db, db:
      db.execute('UPDATE scheduled_tasks SET enabled=1,schedule_json=? WHERE task_id=?', ('{}', 'fixture-task'))
    with self.assertRaises(ValueError):
      local_endpoint.resolve(c)

  def test_compat_requires_terminal_filter_signature_and_no_coalescing(self):
    c = self.database_config()
    path = c['t3Compatibility']['database']
    with closing(sqlite3.connect(path)) as db:
      original = json.loads(db.execute('SELECT schedule_json FROM scheduled_tasks WHERE task_id=?',
                                      ('fixture-task',)).fetchone()[0])
    variants = []
    for signature in [None, {**poll.SIGNATURE, 'header': 'another-header'},
                      {**poll.SIGNATURE, 'encoding': 'base64'}]:
      variants.append({**original, 'signature': signature})
    variants.append({**original, 'filters': [f for f in original['filters'] if f['path'] != 'body.event']})
    for extra in [{'coalesceKey': '{{body.watchId}}'}, {'coalesceWindowSeconds': 120}]:
      variants.append({**original, 'dedupe': {**original['dedupe'], **extra}})
    for schedule in variants:
      with closing(sqlite3.connect(path)) as db, db:
        db.execute('UPDATE scheduled_tasks SET schedule_json=? WHERE task_id=?',
                   (json.dumps(schedule), 'fixture-task'))
      with self.assertRaises(ValueError):
        local_endpoint.resolve(c)

  def test_compat_detects_same_executable_process_reuse(self):
    c = self.database_config()
    for changes in [{'bootId': 'different-boot'}, {'startTicks': c['t3Compatibility']['runtimeIdentity']['startTicks'] + 1}]:
      altered = {**c, 't3Compatibility': {**c['t3Compatibility'],
                 'runtimeIdentity': {**c['t3Compatibility']['runtimeIdentity'], **changes}}}
      with self.assertRaises(ValueError):
        local_endpoint.resolve(altered)

  def test_compat_can_use_explicit_https_transport_without_connect(self):
    c = self.database_config()
    c['httpsOrigin'] = 'https://host.example.ts.net'
    credentials = local_endpoint.resolve(c)
    self.assertEqual(credentials['url'], 'https://host.example.ts.net/api/hooks/fixture-task/synthetic-secret-token')
    self.assertEqual(credentials['signingKey'], KEY)

  def test_schedule_identity_is_encoded_as_a_path_segment(self):
    c = self.database_config()
    c['scheduledTaskId'] = 'fixture task/æ?'
    with closing(sqlite3.connect(c['t3Compatibility']['database'])) as db, db:
      db.execute('UPDATE scheduled_tasks SET task_id=? WHERE task_id=?',
                 (c['scheduledTaskId'], 'fixture-task'))
    self.assertEqual(local_endpoint.resolve(c)['url'],
                     'http://127.0.0.1:12345/api/hooks/fixture%20task%2F%C3%A6%3F/synthetic-secret-token')

  def test_legacy_runtime_fingerprints_do_not_block_compatible_store(self):
    c = self.database_config()
    c['t3Compatibility'].update(runtimeSha256='old-executable-hash',
                                runtimeArtifacts=[{'path':'/missing/old/app.asar','sha256':'old-archive-hash'}])
    self.assertEqual(local_endpoint.resolve(c)['signingKey'], KEY)
    with closing(sqlite3.connect(c['t3Compatibility']['database'])) as db, db:
      db.execute('ALTER TABLE scheduled_tasks RENAME COLUMN webhook_token TO incompatible_token')
    with self.assertRaises(sqlite3.OperationalError):
      local_endpoint.resolve(c)

  def service_config(self):
    c = self.database_config()
    c['t3Compatibility'].pop('runtimePid')
    c['t3Compatibility'].pop('runtimeIdentity')
    c['t3Compatibility']['runtimeUnit'] = 'fixture-t3.service'
    c['endpointTimeout'], c['httpTimeout'] = 10, 1
    self.service_state = self.root / 'service.json'
    ctl = self.root / 'systemctl'
    ctl.write_text('#!' + sys.executable + '\nimport json\nfrom pathlib import Path\n'
                   'for k,v in json.loads(Path(' + repr(str(self.service_state)) + ').read_text()).items():\n'
                   ' print(k+"="+str(v))\n')
    ctl.chmod(0o700)
    c['systemctl'] = str(ctl)
    c['endpointCommand'] = [sys.executable, '-B', str(HERE / 'local_endpoint.py'), '--config', str(self.config_path)]
    self.c = c
    self.config_path.write_text(json.dumps(c))
    return c

  def runtime_server(self, c, port=0, database=None, host='127.0.0.1', executable=None):
    """A real child owns a synthetic SQLite file and loopback HTTP listener."""
    script = self.root / 'runtime.py'
    script.write_text('''import hashlib,hmac,json,sqlite3,sys
from http.server import HTTPServer,BaseHTTPRequestHandler
from pathlib import Path
db=sqlite3.connect(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_POST(self):
  body=self.rfile.read(int(self.headers['Content-Length']))
  key=b'synthetic-signing-key-for-disposable-tests'
  signature='sha256='+hmac.new(key,body,hashlib.sha256).hexdigest()
  valid=hmac.compare_digest(self.headers.get('x-t3-notify-signature',''),signature)
  if valid:Path(sys.argv[4]).write_bytes(body)
  self.send_response(202 if valid else 401)
  self.send_header('x-t3-hook-outcome','accepted' if valid else 'rejected_signature')
  self.end_headers()
class Server(HTTPServer):
 address_family=__import__('socket').AF_INET6 if ':' in sys.argv[2] else __import__('socket').AF_INET
server=Server((sys.argv[2],int(sys.argv[3])),Handler)
print(json.dumps({'port':server.server_port}),flush=True)
server.serve_forever()
''')
    environment = dict(os.environ)
    if executable:
      environment['PYTHONHOME'] = sys.base_prefix
    process = subprocess.Popen([executable or sys.executable, str(script), database or c['t3Compatibility']['database'],
                                host, str(port), str(self.root / 'received.json')],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, env=environment)
    def close():
      if process.poll() is None:
        process.terminate()
      process.wait(timeout=5)
      process.stdout.close()
    self.addCleanup(close)
    self.assertTrue(select.select([process.stdout], [], [], 5)[0], 'Fixture startup timed out')
    ready = json.loads(process.stdout.readline())
    self.service_state.write_text(json.dumps({'LoadState': 'loaded', 'ActiveState': 'active',
                                            'MainPID': process.pid}))
    address = '[' + host + ']' if ':' in host else host
    c['t3Compatibility']['origin'] = f'http://{address}:{ready["port"]}'
    self.config_path.write_text(json.dumps(c))
    return process, ready['port']

  def test_compatible_binary_upgrade_retries_pending_event_without_rebinding_config(self):
    c = self.service_config()
    first, port = self.runtime_server(c)
    before = Path(c['t3Compatibility']['database']).read_bytes()
    self.assertEqual(local_endpoint.resolve(c)['signingKey'], KEY)
    first.terminate(); first.wait(timeout=5)
    self.service_state.write_text(json.dumps({'LoadState': 'loaded', 'ActiveState': 'inactive', 'MainPID': 0}))
    with self.assertRaises(RuntimeError):
      self.tick(deliver=poll.post)
    pending = (self.state / 'pending-terminal.json').read_bytes()
    config = self.config_path.read_bytes()
    upgraded = self.root / 'upgraded-python'
    shutil.copyfile('/proc/self/exe', upgraded)
    with upgraded.open('ab') as stream:
      stream.write(b'\ncompatible-fixture-upgrade\n')
    upgraded.chmod(0o700)
    self.assertNotEqual(hashlib.sha256(upgraded.read_bytes()).hexdigest(),
                        hashlib.sha256(Path('/proc/self/exe').read_bytes()).hexdigest())
    replacement, _ = self.runtime_server(c, port, executable=str(upgraded))
    self.assertNotEqual(first.pid, replacement.pid)
    self.assertEqual(self.config_path.read_bytes(), config)
    def no_lookup(_):
      self.fail('Pending delivery must not rerun the job adapter')
    self.assertEqual(self.tick(fetch=no_lookup, deliver=poll.post), 'notified')
    self.assertEqual((self.state / 'pending-terminal.json').read_bytes(), pending)
    self.assertEqual(json.loads((self.root / 'received.json').read_text())['eventId'], json.loads(pending)['eventId'])
    self.assertEqual(Path(c['t3Compatibility']['database']).read_bytes(), before)
    self.assertEqual(len(self.stops), 1)

  def test_service_runtime_rejects_wrong_listener_database_or_selector(self):
    c = self.service_config()
    process, port = self.runtime_server(c)
    self.assertEqual(local_endpoint.resolve(c)['signingKey'], KEY)
    for change in [{'origin': f'http://127.0.0.1:{port % 65535 + 1}'},
                   {'runtimePid': process.pid}, {'runtimeUnit': '../fixture-t3.service'}]:
      with self.assertRaises(ValueError):
        local_endpoint.resolve({**c, 't3Compatibility': {**c['t3Compatibility'], **change}})
    wrong_db = self.root / 'other.sqlite'
    shutil.copyfile(c['t3Compatibility']['database'], wrong_db)
    with self.assertRaises(ValueError):
      local_endpoint.resolve({**c, 't3Compatibility': {**c['t3Compatibility'], 'database': str(wrong_db)}})
    # A listener owned by another process in the same network namespace is insufficient.
    self.service_state.write_text(json.dumps({'LoadState': 'loaded', 'ActiveState': 'active', 'MainPID': os.getpid()}))
    with closing(sqlite3.connect(c['t3Compatibility']['database'])):
      with self.assertRaises(ValueError):
        local_endpoint.resolve(c)

  def test_service_change_during_resolution_is_rejected(self):
    c = self.service_config()
    process, port = self.runtime_server(c)
    connect = sqlite3.connect
    def restart(*args, **kwargs):
      connection = connect(*args, **kwargs)
      process.terminate(); process.wait(timeout=5)
      self.runtime_server(c, port)
      return connection
    with patch.object(local_endpoint.sqlite3, 'connect', side_effect=restart):
      with self.assertRaises(ValueError):
        local_endpoint.resolve(c)

  def test_service_unavailable_does_not_read_credentials(self):
    c = self.service_config()
    process, _ = self.runtime_server(c)
    for state in [{'LoadState': 'not-found', 'ActiveState': 'inactive', 'MainPID': 0},
                  {'LoadState': 'loaded', 'ActiveState': 'deactivating', 'MainPID': process.pid},
                  {'LoadState': 'loaded', 'ActiveState': 'active', 'MainPID': 0}]:
      self.service_state.write_text(json.dumps(state))
      with patch.object(local_endpoint.sqlite3, 'connect', side_effect=AssertionError('Credential read')):
        with self.assertRaises(ValueError):
          local_endpoint.resolve(c)

  @unittest.skipUnless(socket.has_ipv6, 'IPv6 is unavailable')
  def test_service_ipv6_listener_ownership(self):
    c = self.service_config()
    try:
      process, _ = self.runtime_server(c, host='::1')
    except (json.JSONDecodeError, OSError):
      self.skipTest('IPv6 loopback is unavailable')
    self.assertEqual(local_endpoint.resolve(c)['signingKey'], KEY)

  @unittest.skipUnless(os.environ.get('T3_NOTIFY_SYSTEMD_TEST') == '1', 'explicit disposable systemd smoke')
  def test_real_user_service_restart_delivers_preserved_event(self):
    c = self.service_config()
    bootstrap, port = self.runtime_server(c)
    bootstrap.terminate(); bootstrap.wait(timeout=5)
    ctl = str(Path(shutil.which('systemctl')).resolve())
    name = 't3-notify-runtime-fixture-' + c['watchId'] + '.service'
    ready = self.root / 'ready.json'
    c['systemctl'] = ctl
    c['t3Compatibility']['runtimeUnit'] = name
    self.config_path.write_text(json.dumps(c))
    def cleanup():
      subprocess.run([ctl, '--user', 'stop', name], capture_output=True, timeout=5)
      subprocess.run([ctl, '--user', 'reset-failed', name], capture_output=True, timeout=5)
    self.addCleanup(cleanup)
    # The launcher exits; the fixture server remains in its own user service.
    subprocess.run(['systemd-run', '--user', '--unit=' + name, '--property=Type=exec',
                    '--property=UMask=0077', '--property=Restart=always', '--property=RestartSec=5',
                    '--property=StandardOutput=file:' + str(ready), '--property=StandardError=null',
                    sys.executable, str(self.root / 'runtime.py'), c['t3Compatibility']['database'],
                    '127.0.0.1', str(port), str(self.root / 'received.json')],
                   capture_output=True, check=True, timeout=5)
    def wait_runtime(different=None):
      deadline = time.monotonic() + 20
      while time.monotonic() < deadline:
        try:
          pid, _ = local_endpoint.runtime_state(c)
          local_endpoint.verify_binding(pid, local_endpoint.urllib.parse.urlsplit(c['t3Compatibility']['origin']),
                                        Path(c['t3Compatibility']['database']))
          if pid != different:
            return pid
        except (OSError, ValueError, RuntimeError):
          pass
        time.sleep(.1)
      self.fail('Disposable user service did not become ready')
    first_pid = wait_runtime()
    subprocess.run([ctl, '--user', 'kill', '--signal=KILL', name], capture_output=True, check=True, timeout=5)
    with self.assertRaises(RuntimeError):
      self.tick(deliver=poll.post)
    pending = (self.state / 'pending-terminal.json').read_bytes()
    second_pid = wait_runtime(first_pid)
    self.assertNotEqual(first_pid, second_pid)
    self.assertEqual(self.tick(deliver=poll.post), 'notified')
    self.assertEqual((self.state / 'pending-terminal.json').read_bytes(), pending)
    self.assertEqual(json.loads((self.root / 'received.json').read_text())['eventId'], json.loads(pending)['eventId'])

  @unittest.skipUnless(os.environ.get('T3_NOTIFY_SYSTEMD_TEST') == '1', 'explicit disposable systemd smoke')
  def test_real_timer_active_terminal_ack_stop(self):
    records = self.serve([(503, 'error'), (202, 'accepted')])
    self.c['adapterTimeout'] = 2
    self.c['endpointTimeout'] = 2
    self.config_path.write_text(json.dumps(self.c))
    timer = poll.unit(self.c) + '.timer'
    service = poll.unit(self.c) + '.service'
    def cleanup():
      subprocess.run([self.c['systemctl'], '--user', 'stop', timer, service], capture_output=True, timeout=5)
      subprocess.run([self.c['systemctl'], '--user', 'reset-failed', service], capture_output=True, timeout=5)
    self.addCleanup(cleanup)
    poll.start(self.c, self.config_path, '1s')
    def wait_for(predicate):
      deadline = time.monotonic() + 20
      while time.monotonic() < deadline:
        if predicate():
          return
        time.sleep(.1)
      self.fail('Disposable timer lifecycle timed out')
    wait_for(lambda: (self.state / 'last-check.json').exists())
    self.assertEqual(records, [])
    active = subprocess.run([self.c['systemctl'], '--user', 'is-active', timer], capture_output=True, timeout=5)
    self.assertEqual(active.stdout.strip(), b'active')
    self.source.write_text(json.dumps({'jobId': 'fixture-job', 'state': 'succeeded', 'exitCode': 0, 'total': 17}))
    wait_for(lambda: (self.state / 'notified.json').exists())
    def inactive():
      return subprocess.run([self.c['systemctl'], '--user', 'is-active', timer],
                            capture_output=True, timeout=5).stdout.strip() in {b'inactive', b'failed', b'unknown'}
    wait_for(inactive)
    self.assertEqual(len(records), 2)
    self.assertEqual(records[0][1], records[1][1])
    self.assertEqual(records[0][2], records[1][2])
    self.assertEqual(records[0][1]['status'], 'succeeded')
    log = (self.state / 'watcher.log').read_text()
    self.assertIn('job_running', log)
    self.assertIn('webhook_accepted', log)
    self.assertIn('poll_failed_retry_next_tick', log)
    self.assertNotIn('fixture-secret', log)


if __name__ == '__main__':
  os.umask(0o077)
  unittest.main(verbosity=2)
