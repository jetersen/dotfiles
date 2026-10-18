"""Run with Python containing tomlkit; never touches the real home directory."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import tomllib
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'nixos/home/configure-ai-mcp.py'


class ConfigureAiMcpTests(unittest.TestCase):
    def test_personal_and_work_settings_preserve_client_state(self):
        for work in (False, True):
            with self.subTest(work=work), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                codex = home / 'custom-codex/config.toml'
                codex.parent.mkdir()
                codex.write_text('model = "keep-me"\n[mcp_servers.other]\nurl = "https://other.invalid"\n[mcp_servers.rea]\ncommand = "npx"\n[mcp_servers.codegraph]\ncommand = "codegraph"\n')
                claude = home / '.claude.json'
                claude.write_text(json.dumps({'theme': 'keep-me', 'mcpServers': {'other': {'url': 'https://other.invalid'}, 'rea': {'command': 'npx'}, 'codegraph': {'command': 'codegraph'}}}))
                env = dict(os.environ, HOME=directory, CODEX_HOME=str(codex.parent))
                command = [sys.executable, str(SCRIPT)]
                if work:
                    endpoint = home / 'work-endpoint'
                    endpoint.write_text('https://logs.invalid/mcp\n')
                    command.append(str(endpoint))
                subprocess.run(command, env=env, check=True)
                settings = tomllib.loads(codex.read_text())
                self.assertEqual(settings['model'], 'keep-me')
                self.assertEqual(settings['mcp_servers']['other']['url'], 'https://other.invalid')
                self.assertNotIn('codegraph', settings['mcp_servers'])
                self.assertNotIn('rea', settings['mcp_servers'])
                self.assertEqual('victorialogs' in settings['mcp_servers'], work)
                client = json.loads(claude.read_text())
                self.assertEqual(client['theme'], 'keep-me')
                self.assertIn('other', client['mcpServers'])
                self.assertNotIn('rea', client['mcpServers'])
                self.assertNotIn('codegraph', client['mcpServers'])
                self.assertEqual('victorialogs' in client['mcpServers'], work)
                if work:
                    self.assertEqual(settings['mcp_servers']['victorialogs']['url'], 'https://logs.invalid/mcp')
                before = (codex.read_bytes(), claude.read_bytes())
                subprocess.run(command, env=env, check=True)
                self.assertEqual(before, (codex.read_bytes(), claude.read_bytes()))
                self.assertEqual(codex.stat().st_mode & 0o777, 0o600)
                self.assertEqual(claude.stat().st_mode & 0o777, 0o600)

    def test_removing_work_profile_removes_only_managed_work_server(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            endpoint = home / 'work-endpoint'
            endpoint.write_text('https://logs.invalid/mcp')
            env = dict(os.environ, HOME=directory, CODEX_HOME=str(home / '.codex'))
            command = [sys.executable, str(SCRIPT)]
            subprocess.run(command + [str(endpoint)], env=env, check=True)
            subprocess.run(command, env=env, check=True)
            codex = tomllib.loads((home / '.codex/config.toml').read_text())
            claude = json.loads((home / '.claude.json').read_text())
            self.assertNotIn('victorialogs', codex.get('mcp_servers', {}))
            self.assertNotIn('victorialogs', claude['mcpServers'])
            self.assertNotIn('codegraph', codex.get('mcp_servers', {}))
            self.assertNotIn('codegraph', claude['mcpServers'])


if __name__ == '__main__':
    unittest.main()
