import base64
import importlib.util
import json
import subprocess
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('multinet', ROOT / 'nixos/modules/tailscale-multinet/control.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def encoded(value):
  return base64.b64encode(json.dumps(value).encode()).decode()


class MultinetTests(unittest.TestCase):
  def test_selection_keeps_saved_only_profiles_disconnected(self):
    with tempfile.TemporaryDirectory() as directory:
      state = Path(directory) / 'state'
      catalog = {pid: {'Key': 'profile-' + pid} for pid in ('2ac3', '30a1', 'saved-only')}
      value = {'_profiles': encoded(catalog),
               '_current-profile': base64.b64encode(b'profile-2ac3').decode(),
               '_profile-network': encoded({'primary': '2ac3', 'secondary': ['30a1'], 'preferred': '30a1'})}
      for pid in ('2ac3', '30a1'):
        value['profile-' + pid] = encoded({'CorpDNS': True, 'OperatorUser': 'joseph'})
      state.write_text(json.dumps(value))
      self.assertEqual(m.selection(state)['secondary'], ['30a1'])
      self.assertEqual(m.selection(state)['preferred'], '30a1')
      value['profile-30a1'] = encoded({'CorpDNS': False, 'OperatorUser': 'joseph'})
      state.write_text(json.dumps(value))
      with self.assertRaisesRegex(RuntimeError, 'accept-dns'):
        m.selection(state)

  def test_full_requires_twenty_seconds_on_same_underlay(self):
    gate = m.Settled()
    self.assertFalse(gate.ready('wifi1', 0))
    self.assertFalse(gate.ready('wifi2', 19))
    self.assertFalse(gate.ready('wifi2', 38))
    self.assertTrue(gate.ready('wifi2', 39))
    self.assertFalse(gate.ready(None, 100))
    self.assertFalse(gate.ready('wifi2', 101))

  def test_failed_daemon_shutdown_never_starts_native_writer(self):
    with patch.object(m, 'ctl') as ctl, patch.object(m, 'active', return_value='active'):
      with self.assertRaisesRegex(RuntimeError, 'still running'):
        m.recover()
      self.assertEqual(ctl.call_count, 1)

  def test_residual_kernel_state_never_starts_native_writer(self):
    with patch.object(m, 'ctl') as ctl, patch.object(m, 'active', return_value='inactive'), \
         patch.object(m, 'no_experiment_routes', side_effect=RuntimeError('residual routes')):
      with self.assertRaisesRegex(RuntimeError, 'residual routes'):
        m.recover()
      self.assertEqual(ctl.call_count, 1)

  def test_recovery_retains_current_credentials_and_replaces_resolver_object(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      marker, verified, confirmed = (root / name for name in ('marker', 'verified', 'confirmed'))
      marker.touch()
      confirmed.touch()
      events = []
      with patch.multiple(m, MARKER=marker, VERIFIED=verified, CONFIRMED=confirmed), \
           patch.object(m, 'ctl', side_effect=lambda *args: events.append(args)), \
           patch.object(m, 'active', return_value='inactive'), \
           patch.object(m, 'no_experiment_routes'), patch.object(m, 'replace_link') as replace, \
           patch.object(m, 'dns_health', side_effect=lambda server: events.append(('health', server))):
        m.recover()
      replace.assert_called_once_with(Path('/etc/resolv.conf'), '/etc/static/resolv.conf')
      self.assertFalse(marker.exists())
      self.assertFalse(confirmed.exists())
      self.assertTrue(verified.exists())
      self.assertEqual(events[-2], ('health', '127.0.0.2'))
      self.assertEqual(events[-1], ('stop', 'tailscale-multinet-deadline.timer'))

  def test_native_recovery_reopens_stale_dns_sockets_before_verifying(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      marker, verified, confirmed = (root / name for name in ('marker', 'verified', 'confirmed'))
      with patch.multiple(m, MARKER=marker, VERIFIED=verified, CONFIRMED=confirmed), \
           patch.object(m, 'ctl') as ctl, patch.object(m, 'active', return_value='inactive'), \
           patch.object(m, 'no_experiment_routes'), \
           patch.object(m, 'dns_health', side_effect=[subprocess.CalledProcessError(9, 'dig'), None]) as health:
        m.recover()
      ctl.assert_any_call('restart', 'dnsdist.service')
      self.assertEqual(health.call_count, 2)
      self.assertTrue(verified.exists())

  def test_failed_dns_retry_does_not_claim_native_verification(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      marker, verified, confirmed = (root / name for name in ('marker', 'verified', 'confirmed'))
      with patch.multiple(m, MARKER=marker, VERIFIED=verified, CONFIRMED=confirmed), \
           patch.object(m, 'ctl'), patch.object(m, 'active', return_value='inactive'), \
           patch.object(m, 'no_experiment_routes'), \
           patch.object(m, 'dns_health', side_effect=RuntimeError('still unavailable')):
        with self.assertRaisesRegex(RuntimeError, 'still unavailable'):
          m.recover()
      self.assertFalse(verified.exists())

  def test_unverified_native_never_arms_or_stops_services(self):
    with tempfile.TemporaryDirectory() as directory, patch.object(m, 'VERIFIED', Path(directory) / 'absent'), \
         patch.object(m, 'ctl') as ctl:
      with self.assertRaisesRegex(RuntimeError, 'not verified'):
        m.start()
      ctl.assert_not_called()

  def test_startup_keeps_independent_deadline_until_restart_is_verified(self):
    with tempfile.TemporaryDirectory() as directory:
      root = Path(directory)
      marker, verified, confirmed, nm = (root / name for name in ('marker', 'verified', 'confirmed', 'dns'))
      verified.touch()
      nm.write_text('nameserver 192.0.2.53\n')
      events = []
      def control(*args):
        events.append(args)
      with patch.multiple(m, MARKER=marker, VERIFIED=verified, CONFIRMED=confirmed, NM_DNS=nm), \
           patch.object(m, 'selection', return_value={'primary': '2ac3'}), \
           patch.object(m, 'ctl', side_effect=control), patch.object(m, 'active', return_value='active'), \
           patch.object(m, 'replace_link'), patch.object(m, 'stop_native'), \
           patch.object(m, 'wait_healthy', side_effect=RuntimeError('failed health')):
        # Fail before touching any real /etc object, after the deadline is armed.
        with patch.object(Path, 'exists', autospec=True, side_effect=lambda path: path == verified):
          with patch.object(Path, 'write_text', side_effect=RuntimeError('resolver write failed')):
            with self.assertRaisesRegex(RuntimeError, 'resolver write failed'):
              m.start()
      self.assertTrue(marker.exists())
      self.assertFalse(confirmed.exists())
      self.assertIn(('restart', 'tailscale-multinet-deadline.timer'), events)
      self.assertNotIn(('stop', 'tailscale-multinet-deadline.timer'), events)
      self.assertNotIn(('start', m.DAEMON), events)

  def test_optional_unconfigured_native_units_do_not_break_startup(self):
    with patch.object(m, 'GUARDS', ('present', 'optional')), \
         patch.object(m, 'command', side_effect=['not-found\n', 'loaded\n']), \
         patch.object(m, 'ctl') as ctl:
      m.stop_native()
    ctl.assert_called_once_with('stop', 'present.service')

  def test_underlay_does_not_trust_vpn_or_changed_primary(self):
    with patch.object(m, 'prop', side_effect=[True, '/one', 'vpn']):
      self.assertEqual(m.underlay(), ('', 0))
    with patch.object(m, 'prop', side_effect=[True, '/one', '802-11-wireless', ['/device'], 100, 4, 1, '/two']):
      self.assertEqual(m.underlay(), ('', 0))


if __name__ == '__main__':
  unittest.main()
