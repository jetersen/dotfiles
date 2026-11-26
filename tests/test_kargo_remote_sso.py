from pathlib import Path
import importlib.util
import json
import shlex
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'nixos/assets/scripts/kargo-remote-sso.py'
spec = importlib.util.spec_from_file_location('kargo_remote_sso', SCRIPT)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

LOGIN = {'apiAddress': 'https://kargo.example.com', 'authMethod': 'sso',
         'bearerToken': 'new-token', 'refreshToken': 'new-refresh'}


class RemoteLoginTests(unittest.TestCase):
    def run_remote(self, options, configs):
        with patch.object(Path, 'exists', return_value=True), \
             patch.object(helper.subprocess, 'check_output', side_effect=configs), \
             patch.object(helper.subprocess, 'run') as run, \
             patch.object(sys, 'argv', ['-', json.dumps(options)]), \
             patch('builtins.print') as output:
            exec(helper.REMOTE_SCRIPT, {})
        return run, json.loads(output.call_args.args[0])

    def test_login_uses_remote_desktop_and_port(self):
        session = {'WAYLAND_DISPLAY': 'wayland-1', 'BROWSER': 'browser'}
        run, result = self.run_remote(
            {'server': LOGIN['apiAddress'], 'port': 8086, 'copy_only': False},
            [json.dumps({}), json.dumps(session), json.dumps({**LOGIN, 'project': 'remote'})])
        args, kwargs = run.call_args
        self.assertEqual(args[0], ['kargo', 'login', LOGIN['apiAddress'], '--sso', '--port', '8086'])
        self.assertEqual(kwargs['env']['WAYLAND_DISPLAY'], 'wayland-1')
        self.assertEqual(kwargs['env']['BROWSER'], 'browser')
        self.assertEqual(result, LOGIN)

    def test_copy_only_uses_saved_server_without_browser(self):
        run, result = self.run_remote({'server': None, 'port': 8086, 'copy_only': True},
                                      [json.dumps(LOGIN)])
        run.assert_not_called()
        self.assertEqual(result, LOGIN)

    def test_copy_only_rejects_wrong_server(self):
        with self.assertRaisesRegex(ValueError, 'requested server'):
            self.run_remote({'server': 'https://other.example.com', 'port': 8086, 'copy_only': True},
                            [json.dumps(LOGIN)])

    def test_preserves_local_project_and_replaces_credentials(self):
        original = {**LOGIN, 'project': 'local', 'refreshToken': 'old-refresh'}
        self.assertEqual(helper.merge_config(original, LOGIN), {**LOGIN, 'project': 'local'})
        without_refresh = {key: value for key, value in LOGIN.items() if key != 'refreshToken'}
        self.assertNotIn('refreshToken', helper.merge_config(original, without_refresh))
        self.assertEqual(original['refreshToken'], 'old-refresh')

    def test_switching_server_drops_old_project(self):
        self.assertEqual(helper.merge_config({'apiAddress': 'https://other', 'project': 'old'}, LOGIN), LOGIN)

    def test_invalid_bundle_is_rejected(self):
        for bundle in ({}, {**LOGIN, 'bearerToken': ''}, {**LOGIN, 'authMethod': 'admin'}):
            with self.subTest(bundle=bundle), self.assertRaises(ValueError):
                helper.merge_config({}, bundle)

    def test_atomic_write_is_private_and_failed_transfer_preserves_config(self):
        real_run = helper.subprocess.run
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'config'
            config.write_text(json.dumps({**LOGIN, 'project': 'local'}))
            with patch.object(sys, 'argv', ['kargo-remote-sso', 'framework', '--config', str(config),
                                           '--server', 'kargo.example.com', '--copy-only']), \
                 patch.object(helper.subprocess, 'run') as remote, \
                 patch('builtins.print'):
                transfer = type('Response', (), {'stdout': json.dumps(LOGIN)})()
                remote.side_effect = lambda command, **kwargs: (
                    transfer if command[0] == 'tailscale' else real_run(command, **kwargs))
                helper.main()
                self.assertEqual(config.stat().st_mode & 0o777, 0o600)
                self.assertEqual(helper.read_config(config), {**LOGIN, 'project': 'local'})
                command = next(call.args[0] for call in remote.call_args_list
                               if call.args[0][0] == 'tailscale')
                options = json.loads(shlex.split(command[-1])[-1])
                self.assertEqual(options['server'], LOGIN['apiAddress'])
                original = config.read_bytes()
                transfer.stdout = json.dumps({})
                with self.assertRaises(ValueError):
                    helper.main()
                self.assertEqual(config.read_bytes(), original)
                self.assertEqual(list(Path(directory).glob('.remote-sso-*')), [])


if __name__ == '__main__':
    unittest.main()
