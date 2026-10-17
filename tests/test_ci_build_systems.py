"""Check host output routing and fail-closed CI root updates without building NixOS."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BuildSystems(unittest.TestCase):
    def run_build(self, outputs, fail=False):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            bin_dir = work / 'bin'
            bin_dir.mkdir()
            nix = bin_dir / 'nix'
            nix.write_text('''#!/usr/bin/env python3
import os, sys
if sys.argv[1] == 'build':
    if os.environ['FAIL_BUILD'] == '1':
        sys.exit(42)
    print(os.environ['SYSTEM_OUTPUTS'])
else:
    print('/nix/store/source', end='')
''')
            store = bin_dir / 'nix-store'
            store.write_text('''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps(sys.argv[1:]) + '\\n')
''')
            nix.chmod(0o755)
            store.chmod(0o755)
            calls = work / 'calls'
            result = subprocess.run(['bash', str(ROOT / 'nixos/ci/build-systems.sh')],
                env={**os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}',
                     'RUNNER_TEMP': str(work), 'CI_GCROOTS': str(work / 'roots'),
                     'CALLS': str(calls), 'SYSTEM_OUTPUTS': json.dumps(outputs),
                     'FAIL_BUILD': '1' if fail else '0'}, capture_output=True, text=True)
            return result, ([json.loads(line) for line in calls.read_text().splitlines()]
                            if calls.exists() else [])

    def test_reordered_results_keep_the_correct_host_roots(self):
        result, calls = self.run_build([
            {'outputs': {'out': '/nix/store/aaa-nixos-system-rocket-26.05'}},
            {'outputs': {'out': '/nix/store/bbb-nixos-system-framework-26.05'}},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 3)
        for call, host, store_hash in zip(calls[:2], ['framework', 'rocket'], ['bbb', 'aaa']):
            self.assertEqual(call[:3], ['--realise', f'/nix/store/{store_hash}-nixos-system-{host}-26.05', '--add-root'])
            self.assertTrue(call[3].endswith('/ci-' + host))
        self.assertEqual(calls[2][1], '/nix/store/source')

    def test_failure_or_ambiguous_outputs_leave_named_roots_untouched(self):
        framework = {'outputs': {'out': '/nix/store/aaa-nixos-system-framework-26.05'}}
        for outputs, fail in [([], True), ([framework], False), ([framework, framework], False)]:
            with self.subTest(outputs=outputs, fail=fail):
                result, calls = self.run_build(outputs, fail)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
