from pathlib import Path
import importlib.util
import json
import sys
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / 'nixos/assets/scripts/argocd-remote-sso.py'
spec = importlib.util.spec_from_file_location('remote_sso', SCRIPT)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class RemoteLoginTests(unittest.TestCase):
    def test_native_grpc_login_uses_remote_desktop_and_exports_context(self):
        context = {'name': 'work', 'server': 'argocd.example.com', 'user': 'work-user'}
        config = {'contexts': [context], 'servers': [{'server': context['server']}],
                  'users': [{'name': context['user'], 'auth-token': 'test-token'}]}
        session = {'WAYLAND_DISPLAY': 'wayland-1', 'BROWSER': 'browser'}
        with patch.object(Path, 'exists', return_value=True), \
             patch.object(helper.subprocess, 'check_output',
                          side_effect=[json.dumps(config), json.dumps(session), json.dumps(config)]), \
             patch.object(helper.subprocess, 'run') as run, \
             patch.object(sys, 'argv', ['-', json.dumps({'server': context['server'],
                                                       'context': 'work', 'copy_only': False})]), \
             patch('builtins.print') as output:
            exec(helper.REMOTE_SCRIPT, {})
        args, kwargs = run.call_args
        self.assertEqual(args[0], ['argocd', 'login', context['server'], '--name', 'work',
                                  '--sso', '--sso-launch-browser', '--sso-port', '8085'])
        self.assertEqual(kwargs['env']['WAYLAND_DISPLAY'], 'wayland-1')
        self.assertEqual(kwargs['env']['BROWSER'], 'browser')
        self.assertEqual(json.loads(output.call_args.args[0])['context'], context)


if __name__ == '__main__':
    unittest.main()
