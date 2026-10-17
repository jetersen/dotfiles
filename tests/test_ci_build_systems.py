"""Check parallel planning and fail-closed CI root updates without building NixOS."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BuildSystems(unittest.TestCase):
    def run_build(self, outputs, fail=False, fail_eval='', plans=None):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            bin_dir = work / 'bin'
            bin_dir.mkdir()
            nix = bin_dir / 'nix'
            nix.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
work = Path(os.environ['WORK'])
a = sys.argv[1:]
if a[0] == 'build' and '--dry-run' in a:
    host = next(x for x in a if x.startswith('.#')).split('.')[2]
    (work / (host + '-started')).write_text(os.environ['XDG_CACHE_HOME'])
    # Both planners must start before either can finish.
    deadline = time.monotonic() + 3
    while not all((work / (h + '-started')).exists() for h in ['framework', 'rocket']):
        if time.monotonic() > deadline:
            sys.exit(43)
        time.sleep(.01)
    if os.environ['FAIL_EVAL'] == host:
        sys.exit(42)
    (work / (host + '-done')).touch()
    print(json.dumps(json.loads(os.environ['PLANS'])[host]))
elif a[0] == 'build':
    (work / 'build-args').write_text(json.dumps(a))
    if not all((work / (h + '-done')).exists() for h in ['framework', 'rocket']):
        sys.exit(44)
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
            if plans is None:
                plans = {h: [{'drvPath': f'/nix/store/aaa-nixos-system-{h}-26.05.drv'}]
                         for h in ['framework', 'rocket']}
            result = subprocess.run(['bash', str(ROOT / 'nixos/ci/build-systems.sh')],
                env={**os.environ, 'PATH': f'{bin_dir}:{os.environ["PATH"]}',
                     'RUNNER_TEMP': str(work), 'CI_GCROOTS': str(work / 'roots'),
                     'WORK': str(work), 'XDG_CACHE_HOME': str(work / 'cache'),
                     'CALLS': str(calls), 'SYSTEM_OUTPUTS': json.dumps(outputs),
                     'FAIL_BUILD': '1' if fail else '0', 'FAIL_EVAL': fail_eval,
                     'PLANS': json.dumps(plans)}, capture_output=True, text=True)
            build_args = work / 'build-args'
            caches = [(work / (h + '-started')).read_text() for h in ['framework', 'rocket']]
            return (result,
                    [json.loads(line) for line in calls.read_text().splitlines()] if calls.exists() else [],
                    json.loads(build_args.read_text()) if build_args.exists() else None,
                    caches)

    def test_parallel_plans_and_reordered_results_keep_correct_host_roots(self):
        result, calls, build, caches = self.run_build([
            {'outputs': {'out': '/nix/store/aaa-nixos-system-rocket-26.05'}},
            {'outputs': {'out': '/nix/store/bbb-nixos-system-framework-26.05'}},
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 3)
        self.assertNotEqual(caches[0], caches[1])
        for call, host, store_hash in zip(calls[:2], ['framework', 'rocket'], ['bbb', 'aaa']):
            self.assertEqual(call[:3], ['--realise', f'/nix/store/{store_hash}-nixos-system-{host}-26.05', '--add-root'])
            self.assertTrue(call[3].endswith('/ci-' + host))
            self.assertIn(f'/nix/store/aaa-nixos-system-{host}-26.05.drv^*', build)
        self.assertEqual(calls[2][1], '/nix/store/source')

    def test_build_failure_or_ambiguous_outputs_leave_named_roots_untouched(self):
        framework = {'outputs': {'out': '/nix/store/aaa-nixos-system-framework-26.05'}}
        for outputs, fail in [([], True), ([framework], False), ([framework, framework], False)]:
            with self.subTest(outputs=outputs, fail=fail):
                result, calls, _, _ = self.run_build(outputs, fail)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])

    def test_evaluation_failure_never_starts_realization(self):
        for host in ['framework', 'rocket']:
            with self.subTest(host=host):
                result, calls, build, _ = self.run_build([], fail_eval=host)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])
                self.assertIsNone(build)

    def test_invalid_plans_never_start_realization(self):
        for plan in [[], [{'drvPath': '/nix/store/wrong.drv'}],
                     [{'drvPath': '/nix/store/aaa-nixos-system-rocket-26.05.drv'}]]:
            with self.subTest(plan=plan):
                result, calls, build, _ = self.run_build([], plans={
                    'framework': plan,
                    'rocket': [{'drvPath': '/nix/store/aaa-nixos-system-rocket-26.05.drv'}],
                })
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])
                self.assertIsNone(build)


if __name__ == '__main__':
    unittest.main()
