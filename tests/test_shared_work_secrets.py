"""Nonsecret fixtures for the shared SOPS boundary and explicit SSH bootstrap."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('ssh_bootstrap', ROOT / 'home/.chezmoiscripts/.init-ssh.py')
SSH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SSH)


class SharedWorkTests(unittest.TestCase):
    def render(self, template, work):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'chezmoi.toml'
            config.write_text('[data]\nisWork = ' + str(work).lower() + '\n')
            fake = Path(directory) / 'sops'
            fake.write_text('#!/bin/sh\ntouch "$SOPS_TEST_MARKER"\nprintf "fixture-work-value"\n')
            fake.chmod(0o755)
            marker = Path(directory) / "sops-called"
            output = subprocess.check_output([
                'chezmoi', '--config', str(config), '--source', str(ROOT / 'home'),
                'execute-template', '--file', str(ROOT / template),
            ], env={**os.environ, 'PATH': directory + os.pathsep + os.environ['PATH'], 'SOPS_TEST_MARKER': str(marker)}, text=True)
            self.assertEqual(marker.exists(), work)
            return output

    def test_personal_ai_has_base_without_work(self):
        output = self.render('home/dot_config/ai/private_AGENTS.md.tmpl', False)
        self.assertIn('Repositories live directly', output)
        self.assertNotIn('fixture-work-value', output)
        self.assertNotIn('@AI_WORK_INSTRUCTIONS@', output)

    def test_work_ai_and_npm_use_shared_secret(self):
        self.assertIn('fixture-work-value', self.render('home/dot_config/ai/private_AGENTS.md.tmpl', True))
        self.assertIn('fixture-work-value', self.render('home/private_dot_npmrc.tmpl', True))
        self.assertIn('/.npm-global', self.render('home/private_dot_npmrc.tmpl', False))
        for template in ('home/dot_aws/private_config.tmpl', 'home/dot_kube/private_config.tmpl',
                         'home/dot_config/varlock/work/private_dot_env.schema.tmpl'):
            self.assertEqual('fixture-work-value', self.render(template, True).strip())
            self.assertEqual('', self.render(template, False).strip())

    def test_no_vault_or_read_source_hook(self):
        config = (ROOT / 'home/.chezmoi.toml.tmpl').read_text()
        self.assertNotIn('read-source-state', config)
        self.assertIn('DOTFILES_WORK', config)
        for path in (ROOT / 'home').rglob('*.tmpl'):
            self.assertNotIn('protonPass', path.read_text())
            self.assertNotIn('output "pass-cli"', path.read_text())

    @unittest.skipIf(os.name == 'nt', 'POSIX permission check')
    def test_explicit_ssh_preserves_existing_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'backup'
            source.write_text('nonsecret fixture')
            Path(str(source) + '.pub').write_text('public fixture')
            destination = Path(directory) / 'ssh'
            SSH.bootstrap(source, destination)
            self.assertEqual((destination / 'id_ed25519').stat().st_mode & 0o777, 0o600)
            with self.assertRaises(ValueError):
                SSH.bootstrap(source, destination)
            self.assertEqual((destination / 'id_ed25519').read_text(), 'nonsecret fixture')


if __name__ == '__main__':
    unittest.main()
