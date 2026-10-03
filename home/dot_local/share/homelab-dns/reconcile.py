#!/usr/bin/env python3
"""Restore MagicDNS link settings and retain private VPN routing domains."""
import argparse
import json
import logging
import re
import subprocess
import time
from pathlib import Path

def run(*args):
    return subprocess.check_output(args, text=True, timeout=10)


def retain_domains(path, domains):
    old = set(path.read_text().splitlines()) if path.exists() else set()
    combined = old | domains
    if combined != old or not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(".tmp")
        temporary.write_text("".join(domain + "\n" for domain in sorted(combined)))
        temporary.chmod(0o644)
        temporary.replace(path)


def reconcile(config):
    domains = json.loads(run("resolvectl", "--json=short", "domain"))
    if not Path("/sys/class/net/tailscale0").exists():
        return
    suffix = config["magic_suffix"]
    current_domains = next((x.get("searchDomains") or [] for x in domains
                            if x.get("ifname") == "tailscale0"), [])
    servers = json.loads(run("resolvectl", "--json=short", "dns"))
    current_dns = next((x.get("servers") or [] for x in servers
                        if x.get("ifname") == "tailscale0"), [])
    if [x["addressString"] for x in current_dns] != ["100.100.100.100"]:
        run("resolvectl", "dns", "tailscale0", "100.100.100.100")
    if [(x["name"], x["routeOnly"]) for x in current_domains] != [(suffix, False)]:
        run("resolvectl", "domain", "tailscale0", suffix)
    if not run("resolvectl", "default-route", "tailscale0").strip().endswith(": no"):
        run("resolvectl", "default-route", "tailscale0", "no")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    config = json.loads(Path("/etc/homelab-dns/config.json").read_text())
    assert config["mode"] == "magic-only"
    assert re.fullmatch(r"[a-z0-9-]+\.ts\.net", config["magic_suffix"])
    last_error = None
    while True:
        try:
            reconcile(config)
            if last_error:
                logging.warning("DNS configuration recovered")
            last_error = None
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            if args.once:
                raise
            message = str(error)
            if message != last_error:
                logging.warning("Will retry DNS configuration: %s", message)
            last_error = message
        if args.once:
            return
        time.sleep(3)


if __name__ == "__main__":
    main()
