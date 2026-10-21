import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
  'display', Path(__file__).resolve().parents[1]
  / 'nixos/hosts/framework/restore-laptop-display.py')
display = importlib.util.module_from_spec(spec)
spec.loader.exec_module(display)


class LaptopDisplayTests(unittest.TestCase):
  @patch.object(display.subprocess, 'run')
  def test_undocking_restores_panel_before_dms_updates(self, run):
    disabled = {'logical': None, 'current_mode': None}
    enabled = {'logical': {'scale': 1.5}, 'current_mode': 0}
    states = [
      {'eDP-1': disabled, 'DP-8': enabled, 'DP-11': enabled},
      {'eDP-1': disabled, 'DP-11': enabled},
      {'eDP-1': disabled},
      {'eDP-1': enabled},
    ]
    events = [json.dumps({'OutputsChanged': {'outputs': outputs}}) for outputs in states]
    display.restore_from_events(events, '/bin/niri')
    run.assert_called_once_with(
      ['/bin/niri', 'msg', 'output', 'eDP-1', 'on'], check=True, timeout=5)

  @patch.object(display.subprocess, 'run')
  def test_leaves_other_layouts_and_dpms_sleep_alone(self, run):
    disabled = {'logical': None, 'current_mode': None}
    enabled = {'logical': {'scale': 1.5}, 'current_mode': 0}
    events = [{'WindowsChanged': {'windows': []}}, {'OutputsChanged': {'outputs': {}}}]
    for outputs in [
      {'eDP-1': enabled},  # DPMS off retains this logical configuration.
      {'DP-8': disabled},
      {'eDP-1': disabled, 'DP-8': disabled},
      {'eDP-1': disabled, 'DP-8': enabled},
    ]:
      events.append({'OutputsChanged': {'outputs': outputs}})
    display.restore_from_events(map(json.dumps, events), '/bin/niri')
    run.assert_not_called()

  @patch.object(display.subprocess, 'run')
  def test_failed_restore_restarts_instead_of_silently_losing_recovery(self, run):
    run.side_effect = subprocess.CalledProcessError(1, 'niri')
    event = json.dumps({'OutputsChanged': {'outputs': {'eDP-1': {'logical': None}}}})
    with self.assertRaises(subprocess.CalledProcessError):
      display.restore_from_events([event], '/bin/niri')


if __name__ == '__main__':
  unittest.main()
