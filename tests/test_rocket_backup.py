"""Exercise archive round trips and mount rejection using temporary files only."""
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import io

ROOT = Path(__file__).resolve().parents[1]


class RocketBackupTests(unittest.TestCase):
    def test_encrypted_round_trip_and_wrong_disk_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            mounts = base / 'mnt'
            mounts.mkdir()
            for name in ('old', 'home', 'srv', 'efi', 'games'):
                (mounts / f'rocket-{name}').mkdir()
            old = mounts / 'rocket-old'
            for name in ('etc/ssh', 'etc/pc2mqtt', 'var/lib/tailscale', 'etc/libvirt',
                         'var/lib/libvirt', 'var/lib/docker/volumes/homelab-forgejo-runner_runner-data/_data',
                         'var/lib/docker/volumes/homelab-forgejo-runner_docker-cache/_data'):
                directory = old / name
                directory.mkdir(parents=True, exist_ok=True)
                (directory / 'fixture').write_bytes(b'private fixture\x00bytes')
            registration = mounts / 'rocket-home/joseph/.local/state/forgejo-runner/registration'
            registration.mkdir(parents=True)
            for name in ('uuid', 'token'):
                (registration / name).write_text('fixture')
            key = base / 'identity'
            with key.open('w') as out:
                subprocess.run(['age-keygen'], stdout=out, stderr=subprocess.DEVNULL, check=True)
            recipient = subprocess.check_output(['age-keygen', '-y', str(key)], text=True).strip()
            bindir = base / 'bin'
            bindir.mkdir()
            findmnt = bindir / 'findmnt'
            findmnt.write_text('''#!/usr/bin/env python3
import os,sys
args=sys.argv
field=args[2]
path=args[-1]
if field=='UUID':
 print('wrong' if os.getenv('WRONG_DISK') else ('d49e4cc0-be81-4381-924a-6891cc37c982' if path.endswith('games') else 'B126-967C' if path.endswith('efi') else 'live' if path=='/' else '20956299-478c-4bbf-8be0-bd0c93caa138'))
elif field=='OPTIONS': print('rw' if path.endswith('games') else 'ro')
elif field=='FSROOT': print('/@' if path.endswith('old') else '/@'+path.rsplit('-',1)[1])
''')
            findmnt.chmod(0o755)
            df = bindir / 'df'
            df.write_text('#!/bin/sh\nprintf "Avail\\n%s\\n" "${MOCK_AVAILABLE:-1099511627776}"\n')
            df.chmod(0o755)
            script = (ROOT / 'scripts/rocket-backup.sh').read_text().replace(
                '[[ $EUID == 0 ]]', 'true').replace('/mnt/rocket-', str(mounts / 'rocket-')).replace(
                'age1u0m8ryqg7hfhuykraxe35v4xzw92a03w9jpt75yv3m57g6pvpp0sf24mdy', recipient)
            env = {**os.environ, 'PATH': str(bindir) + ':' + os.environ['PATH']}
            for override in ({'WRONG_DISK': '1'}, {'MOCK_AVAILABLE': '1'}):
                rejected = subprocess.run(['bash', '-c', script], env={**env, **override}, capture_output=True)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertEqual(list((mounts / 'rocket-games').iterdir()), [])
            profile = mounts / 'rocket-home/joseph/.mozilla/firefox/profile'
            profile.parent.mkdir(parents=True)
            profile.symlink_to('/run/user/1000/psd/profile')
            blocked = subprocess.run(['bash', '-c', script], env=env, capture_output=True)
            self.assertNotEqual(blocked.returncode, 0)
            self.assertIn(b'volatile storage', blocked.stderr)
            self.assertEqual(list((mounts / 'rocket-games').iterdir()), [])
            profile.unlink()
            result = subprocess.run(['bash', '-c', script], env=env, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            backup, = (mounts / 'rocket-games').iterdir()
            self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
            archives = list(backup.glob('*.age'))
            self.assertEqual(len(archives), 4)
            for archive in archives:
                encrypted = subprocess.check_output(['age', '-d', '-i', str(key), str(archive)])
                content = subprocess.check_output(['zstd', '-d'], input=encrypted)
                with tarfile.open(fileobj=io.BytesIO(content)) as tar:
                    names = tar.getnames()
                    self.assertTrue(names)
                    if archive.name.startswith('system-state'):
                        self.assertEqual(tar.extractfile('etc/pc2mqtt/fixture').read(), b'private fixture\x00bytes')


if __name__ == '__main__':
    unittest.main()
