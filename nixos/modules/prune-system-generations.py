"""Bound system-profile retention without removing booted or active generations."""

import argparse
import re
import subprocess
import time
from pathlib import Path


def expired_generations(profile, protected, now):
    generations = []
    for link in profile.parent.glob(f"{profile.name}-*-link"):
        match = re.fullmatch(re.escape(profile.name) + r"-(\d+)-link", link.name)
        if match:
            generations.append((int(match[1]), link))
    generations.sort(reverse=True)
    keep = {number for number, _ in generations[:5]}
    cutoff = now - 7 * 24 * 60 * 60
    return [
        number
        for number, link in generations
        if number not in keep
        and link.lstat().st_mtime < cutoff
        and link.resolve(strict=True) not in protected
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nix-env", default="nix-env")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    profile = Path("/nix/var/nix/profiles/system")
    # Fail closed if any identity is unavailable. Never prune user profiles.
    protected = {
        path.resolve(strict=True)
        for path in (profile, Path("/run/current-system"), Path("/run/booted-system"))
    }
    expired = expired_generations(profile, protected, time.time())
    print(f"Expired system generations: {expired}", flush=True)
    if expired:
        subprocess.run(
            [args.nix_env, "--profile", str(profile), "--delete-generations"]
            + (["--dry-run"] if args.dry_run else [])
            + [str(number) for number in expired],
            check=True,
        )


if __name__ == "__main__":
    main()
