"""Exercise Git aliases and SSH signing templates with isolated repositories and keys."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RENDERER = r'''
package main
import (
  "encoding/json"
  "os"
  "text/template"
)
func main() {
  var data struct {
    Values map[string]any
    Keys []map[string]string
  }
  if err := json.NewDecoder(os.Stdin).Decode(&data); err != nil { panic(err) }
  source, err := os.ReadFile(os.Args[1]); if err != nil { panic(err) }
  funcs := template.FuncMap{"gitHubKeys": func(user string) []map[string]string {
    if user != "jetersen" { panic("unexpected GitHub user") }; return data.Keys
  }}
  t, err := template.New("signers").Funcs(funcs).Parse(string(source))
  if err != nil { panic(err) }
  if err := t.Execute(os.Stdout, data.Values); err != nil { panic(err) }
}
'''


class GitConfigTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
        self.env.update(
            HOME=str(self.root), GIT_CONFIG_NOSYSTEM='1',
            GIT_CONFIG_GLOBAL=str(ROOT / 'home/dot_config/git/aliases'),
            GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.test',
            GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.test',
        )
        self.repo = self.root / 'repo'
        self.git('init', '--quiet', '--initial-branch=feature', str(self.repo), cwd=self.root)
        self.git('commit', '--quiet', '--allow-empty', '-m', 'base')

    def git(self, *args, cwd=None):
        return subprocess.check_output(
            ['git', *args], cwd=cwd or self.repo, env=self.env,
            text=True, stderr=subprocess.PIPE,
        ).strip()

    def test_default_branch_fallbacks_and_precedence(self):
        self.assertEqual(self.git('defaultbranch'), 'main')
        for branch in ('trunk', 'master', 'main'):
            self.git('branch', branch)
            self.assertEqual(self.git('defaultbranch'), branch)
        self.git('branch', 'stable')
        self.git('update-ref', 'refs/remotes/origin/stable', 'HEAD')
        self.git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/stable')
        self.assertEqual(self.git('defaultbranch'), 'stable')
        self.git('branch', '-D', 'stable')
        self.assertEqual(self.git('defaultbranch'), 'origin/stable')
        self.git('update-ref', '-d', 'refs/remotes/origin/stable')
        self.assertEqual(self.git('defaultbranch'), 'main')

    def test_remote_only_fallbacks(self):
        for branch in ('trunk', 'master', 'main'):
            self.git('update-ref', 'refs/remotes/origin/' + branch, 'HEAD')
            self.assertEqual(self.git('defaultbranch'), 'origin/' + branch)

    def test_history_aliases_use_selected_branch_and_forward_arguments(self):
        self.git('branch', 'stable')
        self.git('commit', '--quiet', '--allow-empty', '-m', 'feature change')
        self.git('checkout', '--quiet', 'stable')
        self.git('commit', '--quiet', '--allow-empty', '-m', 'upstream change')
        self.git('update-ref', 'refs/remotes/origin/stable', 'HEAD')
        self.git('symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/stable')
        self.git('checkout', '--quiet', 'feature')
        for remote_only in (False, True):
            with self.subTest(remote_only=remote_only):
                if remote_only:
                    self.git('branch', '-D', 'stable')
                self.assertEqual(self.git('missing', '--format=%s', '--no-graph'), 'upstream change')
                self.assertEqual(self.git('new', '--format=%s', '--no-graph'), 'feature change')

    def test_allowed_signers_render_and_verify_both_identities(self):
        renderer = self.root / 'render.go'
        renderer.write_text(RENDERER)
        executable = self.root / 'render'
        # Standard Go templates match chezmoi's syntax; stub only its network lookup.
        subprocess.run(['go', 'build', '-o', str(executable), str(renderer)], check=True,
                       env=self.env, capture_output=True)
        keys = []
        for name in ('key1', 'key2'):
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '',
                            '-C', 'fixture', '-f', str(self.root / name)],
                           check=True, env=self.env, capture_output=True)
            keys.append({'Key': (self.root / (name + '.pub')).read_text().strip()})
        message = self.root / 'message'
        message.write_text('synthetic signature fixture\n')
        subprocess.run(['ssh-keygen', '-Y', 'sign', '-f', str(self.root / 'key1'),
                        '-n', 'git', str(message)], check=True, env=self.env, capture_output=True)
        for work in (False, True):
            for system in ('linux', 'darwin', 'windows'):
                for email in ('work@example.test', 'personal@example.test'):
                    with self.subTest(isWork=work, system=system, workEmail=email):
                        values = {'personalEmail': 'personal@example.test', 'workEmail': email,
                                  'isWork': work, 'chezmoi': {'os': system}}
                        rendered = subprocess.check_output(
                            [str(executable), str(ROOT / 'home/dot_config/git/allowed_signers.tmpl')],
                            input=json.dumps({'Values': values, 'Keys': keys}), text=True,
                            env=self.env,
                        )
                        identities = {'personal@example.test', email}
                        self.assertEqual(len(rendered.strip().splitlines()), len(keys) * len(identities))
                        signers = self.root / 'allowed_signers'
                        signers.write_text(rendered)
                        for identity in identities:
                            subprocess.run(
                                ['ssh-keygen', '-Y', 'verify', '-f', str(signers), '-I', identity,
                                 '-n', 'git', '-s', str(message) + '.sig'],
                                input=message.read_bytes(), check=True, env=self.env,
                                capture_output=True,
                            )


if __name__ == '__main__':
    unittest.main()
