"""Publish deployable closures and check binary availability without building them."""

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor
import glob
import json
import netrc
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
from urllib.error import HTTPError
from urllib.parse import parse_qsl, urlencode, urljoin, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


PRIVATE = "https://nix-cache.jetersen.dev/workstations"
PUBLIC = "https://cache.nixos.org"
STORE_NAME = re.compile(r"[0-9abcdfghijklmnpqrsvwxyz]{32}-[^/\s]+\Z")


def store_path(path):
  if not path.startswith("/nix/store/") or not STORE_NAME.fullmatch(path[11:]):
    raise ValueError(f"Invalid store path: {path!r}")
  return path


class SafeRedirect(HTTPRedirectHandler):
  def redirect_request(self, request, fp, code, message, headers, newurl):
    if urlsplit(newurl).scheme != "https":
      raise RuntimeError("Cache redirect must use HTTPS")
    redirected = super().redirect_request(request, fp, code, message, headers, newurl)
    if urlsplit(request.full_url).netloc != urlsplit(newurl).netloc:
      redirected.remove_header("Authorization")
    return redirected


class Cache:
  def __init__(self, url, credentials=None):
    self.url = url.rstrip("/") + "/"
    if urlsplit(self.url).scheme != "https":
      raise ValueError("Cache URL must use HTTPS")
    self.credentials = credentials

  def request(self, url, method="GET"):
    request = Request(url, method=method)
    if self.credentials and urlsplit(url).netloc == urlsplit(self.url).netloc:
      user, _, password = self.credentials
      encoded = base64.b64encode(f"{user}:{password}".encode()).decode()
      request.add_header("Authorization", "Basic " + encoded)
    try:
      # Each worker owns its opener; no shared HTTP/auth state.
      with build_opener(SafeRedirect()).open(request, timeout=15) as response:
        return response.read(1024 * 1024) if method == "GET" else b""
    except HTTPError as error:
      if error.code == 404:
        return None
      raise RuntimeError(f"Cache returned HTTP {error.code}: {url}") from None

  def probe(self, path):
    store_path(path)
    data = self.request(self.url + Path(path).name[:32] + ".narinfo")
    if data is None:
      return None
    fields = {}
    for line in data.decode().splitlines():
      key, value = line.split(": ", 1) if ": " in line else (line.rstrip(":"), "")
      if key in fields and key != "Sig":
        raise ValueError(f"Duplicate narinfo field for {path}: {key}")
      fields[key] = value
    if fields.get("StorePath") != path or not fields.get("NarHash") or not fields.get("Sig"):
      raise ValueError(f"Incomplete or mismatched narinfo for {path}")
    references = {store_path("/nix/store/" + name) for name in fields.get("References", "").split()}
    nar_url = urljoin(self.url, fields["URL"])
    if urlsplit(nar_url).scheme != "https":
      raise ValueError(f"NAR URL must use HTTPS: {path}")
    # Attic refreshes last_accessed_at on NAR requests, not narinfo queries.
    # HEAD checks availability and refreshes retention without downloading NARs.
    if self.request(nar_url, method="HEAD") is None:
      return None
    return references


def parallel(items, operation):
  pool = ThreadPoolExecutor(max_workers=16)
  try:
    results = dict(zip(items, pool.map(operation, items)))
  except BaseException:
    pool.shutdown(wait=False, cancel_futures=True)
    raise
  else:
    pool.shutdown()
    return results


def available(path, caches):
  errors = []
  for cache in caches:
    try:
      references = cache.probe(path)
    except (OSError, RuntimeError) as error:
      errors.append(str(error))
      continue
    if references is not None:
      return references
  detail = "; ".join(errors)
  raise RuntimeError(f"Binary not available from any configured cache: {path} {detail}")


def verify(roots, caches, expected=None):
  """Walk remote references, including paths absent from this machine's store."""
  seen = set()
  pending = {store_path(path) for path in roots}
  while pending:
    batch = sorted(pending - seen)
    if not batch:
      break
    results = parallel(batch, lambda path: available(path, caches))
    if expected is not None:
      for path, references in results.items():
        if references != set(expected[path]["references"]):
          raise ValueError(f"Cached references differ for {path}")
    seen.update(batch)
    pending = set().union(*results.values()) - seen
  print(f"Verified {len(seen)} cached system paths.", flush=True)
  return seen


def inventory(roots):
  return json.loads(subprocess.check_output([
    "nix", "path-info", "--recursive", "--json", "--json-format", "1", *roots,
  ]))


def publication_plan(paths, required, upstream, max_bytes):
  candidates = sorted(paths)
  public = parallel(candidates, upstream.probe)
  selected = []
  for path in candidates:
    metadata = paths[path]
    if public[path] is not None:
      if public[path] != set(metadata["references"]):
        raise ValueError(f"Upstream references differ for {path}")
      continue
    if path in required or metadata["narSize"] < max_bytes:
      selected.append(path)
      if metadata["narSize"] >= max_bytes:
        print(f"Caching large deployment dependency absent upstream: {path}", flush=True)
  return selected


def publish(args, private, public):
  temporary = Path(os.environ["RUNNER_TEMP"])
  systems = [(temporary / f"{host}-system").read_text().strip() for host in ("framework", "rocket")]
  extras = []
  for name in ("project-shells", "check-outputs", "pc2mqtt-deps"):
    extras.extend((temporary / name).read_text().splitlines())
  required = inventory(systems)
  paths = inventory([*systems, *extras])
  selected = publication_plan(paths, required, public, args.max_mib * 1024 * 1024)
  if selected:
    subprocess.run([
      "attic", "push", "--no-closure", "--stdin", "--ignore-upstream-cache-filter",
      "homelab:workstations",
    ], input="".join(path + "\n" for path in selected), text=True, check=True)
  # A successful upload alone is insufficient. Check the complete remote graph
  # and NAR endpoints before the workflow is allowed to send deployment hints.
  verify(systems, [public, private], expected=required)


def pinned_flake(flake, revision):
  if not re.fullmatch(r"[0-9a-f]{40}", revision):
    raise ValueError("Expected an immutable Git revision")
  url = urlsplit(flake)
  if url.scheme != "git+https" or url.fragment:
    raise ValueError("Expected a Git HTTPS flake without a fragment")
  query = [(key, value) for key, value in parse_qsl(url.query) if key != "rev"]
  return urlunsplit(url._replace(query=urlencode([*query, ("rev", revision)])))


def upgrade(args, caches):
  metadata = json.loads(subprocess.check_output([
    "nix", "flake", "metadata", "--json", "--refresh", "--no-write-lock-file", args.flake,
  ]))
  flake = pinned_flake(args.flake, metadata["locked"]["rev"])
  target = subprocess.check_output([
    "nix", "eval", "--raw", "--no-write-lock-file",
    f"{flake}#nixosConfigurations.{args.host}.config.system.build.toplevel",
  ], text=True).strip()
  verify([target], caches)
  # Verification and activation must select the same commit even if main moves.
  signal.alarm(0)
  subprocess.run([
    args.rebuild, "switch", "--no-write-lock-file", "--flake", f"{flake}#{args.host}",
  ], check=True)


def refresh(private):
  links = ["/run/current-system", "/run/booted-system", *glob.glob("/nix/var/nix/profiles/system-*-link")]
  roots = sorted({str(Path(link).resolve(strict=True)) for link in links if Path(link).exists()})
  if not roots:
    raise RuntimeError("No installed NixOS generations found")
  paths = inventory(roots)
  results = parallel(sorted(paths), private.probe)
  count = sum(value is not None for value in results.values())
  print(f"Refreshed retention for {count} private-cache paths used by installed generations.", flush=True)


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("mode", choices=["publish", "upgrade", "refresh", "verify"])
  parser.add_argument("--netrc", required=True)
  parser.add_argument("--timeout", type=int, default=900)
  parser.add_argument("--max-mib", type=int, default=512)
  parser.add_argument("--flake")
  parser.add_argument("--host", choices=["framework", "rocket"])
  parser.add_argument("--rebuild")
  parser.add_argument("paths", nargs="*")
  args = parser.parse_args()
  if args.timeout <= 0 or args.max_mib < 0:
    parser.error("timeout must be positive and max-mib must be nonnegative")
  if args.mode == "upgrade" and not all((args.flake, args.host, args.rebuild)):
    parser.error("upgrade requires --flake, --host and --rebuild")
  credentials = netrc.netrc(args.netrc).authenticators(urlsplit(PRIVATE).hostname)
  if not credentials:
    parser.error("netrc has no private-cache credentials")
  private, public = Cache(PRIVATE, credentials), Cache(PUBLIC)

  def timed_out(signum, frame):
    raise TimeoutError("Cache readiness deadline exceeded; leaving the running system unchanged")

  signal.signal(signal.SIGALRM, timed_out)
  signal.alarm(args.timeout)
  try:
    if args.mode == "publish":
      publish(args, private, public)
    elif args.mode == "upgrade":
      upgrade(args, [public, private])
    elif args.mode == "refresh":
      refresh(private)
    else:
      if not args.paths:
        parser.error("verify requires system store paths")
      verify(args.paths, [public, private])
  finally:
    signal.alarm(0)


if __name__ == "__main__":
  try:
    main()
  except (OSError, RuntimeError, ValueError, KeyError, subprocess.CalledProcessError) as error:
    print(f"Cache policy: {error}", file=sys.stderr)
    sys.exit(1)
