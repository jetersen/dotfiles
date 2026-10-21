"""Publish boot targets to NixOS's standard profile without owning manual history."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def generations(profile):
    pattern = re.compile(re.escape(profile.name) + r"-([0-9]+)-link")
    result = {}
    for link in profile.parent.glob(f"{profile.name}-*-link"):
        match = pattern.fullmatch(link.name)
        if match and link.is_symlink():
            stat = link.lstat()
            result[match[1]] = {
                "target": os.readlink(link),
                "inode": stat.st_ino,
                "mtime": stat.st_mtime_ns,
            }
    return result


def save_state(path, owned):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
        temporary = Path(f.name)
        try:
            json.dump(owned, f, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


def install(args):
    target = args.target.resolve(strict=True)
    # Reject mistakes before modifying either profile or the ESP.
    if not (target / "boot.json").is_file():
        raise ValueError(f"Not a NixOS boot target: {target}")
    args.state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (args.state / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = args.state / "generations.json"
        owned = json.loads(state.read_text()) if state.exists() else {}
        before = generations(args.profile)
        previous = os.readlink(args.profile) if args.profile.is_symlink() else None
        nix_env = [args.nix_env, "--profile", str(args.profile)]
        subprocess.run([*nix_env, "--set", str(target)], check=True)
        after = generations(args.profile)
        retained = {str(Path(v["target"]).resolve()) for v in generations(args.comin).values()}
        # nixos-rebuild sets its own profile before calling this hook. Such
        # generations, and all pre-existing history, remain manually managed.
        if str(target) in retained:
            owned.update({n: v for n, v in after.items() if n not in before})
        save_state(state, owned)
        protected = {str(target), str(args.booted.resolve())}
        if previous:
            protected.add(str((args.profile.parent / previous).resolve()))
        stale = []
        for number, identity in list(owned.items()):
            if after.get(number) != identity:
                # Nix can reuse a generation number after manual deletion.
                del owned[number]
            elif str(Path(identity["target"]).resolve()) not in retained | protected:
                stale.append(number)
        if stale:
            subprocess.run([*nix_env, "--delete-generations", *sorted(stale, key=int)], check=True)
            for number in stale:
                del owned[number]
        save_state(state, owned)
        try:
            subprocess.run([args.installer, str(target), *args.installer_args], check=True)
        except (subprocess.CalledProcessError, OSError):
            # Keep the previous selection rooted, including when signing fails.
            # An installer may already have written part of the ESP; report its
            # failure rather than claiming to undo those writes.
            if previous:
                match = re.fullmatch(re.escape(args.profile.name) + r"-([0-9]+)-link", previous)
                if match:
                    subprocess.run([*nix_env, "--switch-generation", match[1]], check=True)
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--nix-env", required=True)
    parser.add_argument("--installer", required=True)
    parser.add_argument("--profile", type=Path, default=Path("/nix/var/nix/profiles/system"))
    parser.add_argument("--comin", type=Path, default=Path("/nix/var/nix/profiles/system-profiles/comin"))
    parser.add_argument("--state", type=Path, default=Path("/var/lib/comin/standard-boot-profile"))
    parser.add_argument("--booted", type=Path, default=Path("/run/booted-system"))
    parser.add_argument("target", type=Path)
    parser.add_argument("installer_args", nargs=argparse.REMAINDER)
    install(parser.parse_args())


if __name__ == "__main__":
    main()
