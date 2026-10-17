#!/usr/bin/env python3
"""Explicitly import an existing personal SSH identity; never run by chezmoi."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess


def bootstrap(source, destination):
    source = Path(source).expanduser()
    destination = Path(destination).expanduser()
    public = Path(str(source) + '.pub')
    if not source.is_file() or not public.is_file():
        raise ValueError('Provide an existing private key and its .pub companion')
    destination.mkdir(mode=0o700, parents=True, exist_ok=True)
    private_target = destination / 'id_ed25519'
    public_target = destination / 'id_ed25519.pub'
    if private_target.exists() or public_target.exists():
        raise ValueError('Destination identity already exists; refusing to overwrite')
    created = []
    try:
        for src, target in [(source, private_target), (public, public_target)]:
            descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            created.append(target)
            with os.fdopen(descriptor, 'wb') as output:
                if os.name == 'nt':
                    # Restrict access before writing any private data.
                    sid = subprocess.check_output(['whoami', '/user', '/fo', 'csv', '/nh'], text=True).strip().split(',')[-1].strip('"')
                    subprocess.run(['icacls', str(target), '/inheritance:r', '/grant:r', f'*{sid}:(F)'], check=True, stdout=subprocess.DEVNULL)
                with src.open('rb') as input_file:
                    shutil.copyfileobj(input_file, output)
    except BaseException:
        for target in created:
            target.unlink()
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', help='Securely restored private key path, with .pub companion')
    parser.add_argument('--destination', default=str(Path.home() / '.ssh'))
    args = parser.parse_args()
    bootstrap(args.source, args.destination)
