"""Fixed-command local control socket and route/DNS reconciliation for work Tailscale."""

import argparse
import http.client
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import struct
import subprocess
import sys
import time
from urllib.parse import quote, urlsplit

ROOT = Path("/var/lib/work-tailnet")
RUN = Path("/run/work-tailnet")
SOCKET = str(RUN / "control.sock")
TS_SOCKET = str(RUN / "tailscaled.sock")
NS = "work-tailnet"


def run(*args):
  return subprocess.check_output(args, text=True, timeout=15).strip()


def tailscale(*args):
  return run("tailscale", "--socket=" + TS_SOCKET, *args)


def profile_info():
  try:
    profiles = json.loads(tailscale("switch", "--list", "--json")) or []
    selected = next((p for p in profiles if p.get("selected")), profiles[0] if profiles else {})
    return {"hasProfile": bool(profiles), "tailnetName": selected.get("tailnet") or ""}
  except (OSError, ValueError, subprocess.SubprocessError):
    return {"hasProfile": None, "tailnetName": ""}


def local_request(method, path, payload=None, expected=200):
  connection = http.client.HTTPConnection("local-tailscaled.sock", timeout=5)
  connection.sock = socket.socket(socket.AF_UNIX)
  try:
    connection.sock.settimeout(5)
    connection.sock.connect(TS_SOCKET)
    connection.request(method, path,
      json.dumps(payload) if payload is not None else None,
      {"Content-Type": "application/json"})
    response = connection.getresponse()
    response.read()  # Prefs may contain credentials; never log the response.
    if response.status != expected:
      raise ValueError(f"Work Tailscale request failed: HTTP {response.status}")
  finally:
    connection.close()


def resume():
  # Resume asynchronously without resetting preferences or waiting for DERP/
  # coordination. A slow reconnect must not make the controller take it down.
  local_request("PATCH", "/localapi/v0/prefs", {"WantRunning": True, "WantRunningSet": True})


def remember_work_tailnet(path, current, personal):
  identity = current.get("StableID")
  if not identity or not personal.get("StableID"):
    raise ValueError("Cannot verify work and personal tailnet identities yet")
  if identity == personal["StableID"]:
    raise ValueError("The work instance is signed into the personal tailnet")
  if path.exists():
    saved = json.loads(path.read_text())
    if saved.get("id") != identity:
      raise ValueError("Selected tailnet differs from the saved work identity")
    return saved
  profiles = json.loads(tailscale("switch", "--list", "--json")) or []
  selected = next((p for p in profiles if p.get("selected")), {})
  saved = {"id": identity, "name": current.get("Name", ""), "profileId": selected.get("id", "")}
  write_json(path, saved)
  return saved


def restore_work_profile(identity, personal_name=""):
  profiles = json.loads(tailscale("switch", "--list", "--json")) or []
  if identity:
    matches = [p for p in profiles if p.get("id") == identity.get("profileId")]
  else:
    matches = [p for p in profiles if p.get("tailnet") != personal_name]
  if len(matches) > 1:
    raise ValueError("Multiple saved work profiles; select the intended account first")
  if not matches or matches[0].get("selected"):
    return False
  local_request("POST", "/localapi/v0/profiles/" + quote(matches[0]["id"], safe=""), expected=204)
  return True


def routes_in(family, tables, namespace=None):
  # Query all tables: querying an empty numbered table fails on a fresh boot.
  args = ["ip"] + (["-n", namespace] if namespace else [])
  return [r for r in json.loads(run(*args, family, "-j", "route", "show", "table", "all"))
    if str(r.get("table", "main")) in tables]


def write_json(path, value):
  content = json.dumps(value, sort_keys=True) + "\n"
  if path.exists() and path.read_text() == content:
    return
  temporary = path.with_suffix(".tmp")
  temporary.write_text(content)
  temporary.replace(path)


def active_ssids():
  # Query active profiles, not the scan cache: an office AP nearby is insufficient.
  uuids = run("nmcli", "-g", "UUID", "connection", "show", "--active").splitlines()
  result = set()
  for uuid in uuids:
    kind = run("nmcli", "-g", "connection.type", "connection", "show", uuid)
    if kind == "802-11-wireless":
      result.add(run("nmcli", "--escape", "no", "-g", "802-11-wireless.ssid", "connection", "show", uuid))
  return result


def wanted(mode, ssids, office_ssids, presence, now):
  if mode == "on":
    return True
  if mode == "off":
    return False
  return bool(ssids & set(office_ssids)) or (
    presence.get("at_work") is True and now < presence.get("expires", 0)
  )


def valid_domains(dns):
  domains = [dns.get("CurrentTailnet", {}).get("MagicDNSSuffix", "")]
  domains += list((dns.get("SplitDNSRoutes") or {}).keys())
  return sorted({d.strip(".").lower() for d in domains if
    re.fullmatch(r"(?=.{1,253}\.?$)[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\.?", d)
    and all(0 < len(label) <= 63 for label in d.rstrip(".").split("."))})


def route_plan(routes, protected):
  """Export only actual accepted work routes; leave local and homelab ranges alone."""
  result = set()
  for route in routes:
    if route.get("dev") != "tailscale-work" or route.get("type", "unicast") != "unicast":
      continue
    dst = route.get("dst", "default")
    if dst == "default":
      continue
    network = ipaddress.ip_network(dst, strict=False)
    if network.prefixlen == 0 or network.is_multicast or network.is_link_local:
      continue
    pieces = [network]
    for reserved in protected:
      if reserved.version != network.version:
        continue
      remaining = []
      for piece in pieces:
        if piece.subnet_of(reserved):
          continue
        remaining.extend(piece.address_exclude(reserved) if reserved.subnet_of(piece) else [piece])
      pieces = remaining
    result.update(map(str, pieces))
  return result


def peer_doh_url(address):
  """Accept only the HTTP DNS endpoint advertised by Tailscale peers."""
  if any(ord(c) <= 32 or ord(c) >= 127 for c in address):
    raise ValueError("Invalid peer DNS URL")
  endpoint = urlsplit(address)
  ip = ipaddress.ip_address(endpoint.hostname or "")
  pool = ipaddress.ip_network("100.64.0.0/10" if ip.version == 4 else "fd7a:115c:a1e0::/48")
  if (endpoint.scheme != "http" or ip not in pool or "%" in str(ip)
      or not endpoint.port or endpoint.username is not None or endpoint.password is not None
      or endpoint.path != "/dns-query" or endpoint.query or endpoint.fragment):
    raise ValueError("Invalid peer DNS URL")
  return endpoint


def dns_plan(domains, dns):
  lines = set()
  peers = {}
  for domain, resolvers in (dns.get("SplitDNSRoutes") or {}).items():
    domain = domain.rstrip(".").lower()
    if domain not in domains:
      continue
    for resolver in resolvers or []:
      address = resolver["Addr"]
      if "://" in address:
        peer_doh_url(address)
        peers.setdefault(domain, []).append(address)
        address = "127.0.0.1#5354"
      else:
        address = str(ipaddress.ip_address(address))
      lines.add(f"server=/{domain}/{address}\n")
  return "".join(sorted(lines)), peers


def protected_routes():
  # The personal tailnet's policy reserves this pool, including future peers.
  result = list(map(ipaddress.ip_network, ["100.99.0.0/16", "100.100.100.100/32"]))
  for family in ("-4", "-6"):
    for route in routes_in(family, {"main", "local", "52"}):
      if route.get("dst", "default") != "default":
        network = ipaddress.ip_network(route["dst"], strict=False)
        if network.prefixlen:
          result.append(network)
  return result


class Controller:
  def __init__(self, default_mode, office_ssids, resolved):
    self.state_path = ROOT / "state.json"
    self.tailnet_path = ROOT / "tailnet.json"
    self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {"mode": default_mode}
    self.office_ssids = office_ssids
    self.resolved = resolved
    self.presence = {}  # Never trust presence retained across reboot or agent restart.
    self.snapshot = {"connected": False, "mode": self.state["mode"], "error": "Starting"}
    self.domains = None
    self.servers = None
    self.peers = None
    self.ssids = set()
    self.wifi_checked = -10

  def request(self, request):
    command = request["command"]
    if command in ("on", "off", "auto"):
      self.state["mode"] = command
      write_json(self.state_path, self.state)
    elif command == "presence":
      # TTL uses this host's monotonic clock, never a timestamp supplied remotely.
      at_work = request["location"] == "work"
      if request["location"] not in ("work", "away"):
        raise ValueError("location must be work or away")
      ttl = int(request.get("ttl", 120))
      if not 1 <= ttl <= 300:
        raise ValueError("presence TTL must be 1..300 seconds")
      self.presence = {"at_work": at_work, "expires": time.monotonic() + ttl}
    elif command != "status":
      raise ValueError("unknown command")
    result = self.snapshot | {"mode": self.state["mode"]}
    if command == "status":
      result |= profile_info()
    return result

  def sync_dns(self, domains, dns=None):
    domains = sorted(domains)
    servers, peers = dns_plan(domains, dns or {})
    if domains == self.domains and servers == self.servers and peers == self.peers:
      return
    # With accept-dns=false, Quad100 only serves MagicDNS. Forward work split
    # domains directly to their advertised resolvers inside the work namespace.
    # dnsmasq cannot speak HTTP; the loopback bridge retains the peer URL/port
    # and DNS discovery, so the connector can learn routes from the replies.
    write_json(RUN / "peer-dns.json", peers)
    temporary = RUN / "dnsmasq.servers.tmp"
    temporary.write_text(servers)
    temporary.chmod(0o644)
    temporary.replace(RUN / "dnsmasq.servers")
    run("systemctl", "kill", "--kill-whom=main", "--signal=HUP", "work-tailnet-dns.service")
    # dnsdist consumes only this validated line list, never executable Lua.
    temporary = RUN / "domains.tmp"
    temporary.write_text("".join(d + "\n" for d in domains))
    temporary.chmod(0o644)
    temporary.replace(RUN / "domains")
    if self.resolved:
      if domains:
        run("resolvectl", "dns", "wt-host", "169.254.77.2")
        run("resolvectl", "default-route", "wt-host", "no")
        run("resolvectl", "domain", "wt-host", *("~" + d for d in domains))
      else:
        run("resolvectl", "revert", "wt-host")
    self.domains = domains
    self.servers = servers
    self.peers = peers

  def sync_routes(self, desired):
    for family in ("-4", "-6"):
      current = {str(ipaddress.ip_network(r["dst"], strict=False)):
        next((metric["mtu"] for metric in r.get("metrics", []) if "mtu" in metric), r.get("mtu"))
        for r in routes_in(family, {"53"})}
      target = {r for r in desired if (":" in r) == (family == "-6")}
      for prefix in sorted(current.keys() - target):
        run("ip", family, "route", "del", prefix, "table", "53")
      for prefix in sorted(prefix for prefix in target if current.get(prefix) != 1280):
        gateway = "169.254.77.2" if family == "-4" else "fd42:77::2"
        run("ip", family, "route", "replace", prefix, "via", gateway, "dev", "wt-host", "table", "53", "mtu", "1280")
    # A DNS reply must not expose a newly learned address until its work route
    # is installed on the host. The unprivileged bridge only reads this receipt.
    write_json(RUN / "exported-routes.json", sorted(desired))

  def reconcile(self):
    mode = self.state["mode"]
    if mode == "auto" and time.monotonic() - self.wifi_checked >= 10:
      self.ssids = active_ssids()
      self.wifi_checked = time.monotonic()
    ssids = self.ssids if mode == "auto" else set()
    enabled = wanted(mode, ssids, self.office_ssids, self.presence, time.monotonic())
    identity = json.loads(self.tailnet_path.read_text()) if enabled and self.tailnet_path.exists() else None
    status = json.loads(tailscale("status", "--json"))
    backend = status.get("BackendState")
    if enabled and backend in ("NeedsLogin", "NoState"):
      personal = json.loads(run("tailscale", "status", "--json"))
      if restore_work_profile(identity, (personal.get("CurrentTailnet") or {}).get("Name", "")):
        status = json.loads(tailscale("status", "--json"))
        backend = status.get("BackendState")
    if not enabled:
      # Clear routes first so an off connection never leaves stale forwarding.
      self.sync_routes(set())
      self.sync_dns([])
      if backend not in ("Stopped", "NeedsLogin", "NoState"):
        tailscale("down")
    elif backend == "Stopped":
      # Does not initiate interactive login or block waiting for SSO.
      tailscale("set", "--accept-dns=false", "--accept-routes=true", "--ssh=false")
      resume()
    connected = enabled and backend == "Running"
    if connected:
      personal = json.loads(run("tailscale", "status", "--json"))
      remember_work_tailnet(self.tailnet_path, status.get("CurrentTailnet") or {}, personal.get("CurrentTailnet") or {})
      work_dns = json.loads(tailscale("dns", "status", "--json"))
      personal_dns = json.loads(run("tailscale", "dns", "status", "--json"))
      work_domains = valid_domains(work_dns)
      # A broad personal ts.net split resolver still yields to the distinct
      # work MagicDNS suffix, just as the host's resolver does for more specific domains.
      personal_domains = [d for d in valid_domains(personal_dns) if d != "ts.net"] + ["jetersen.dev"]
      # Matching suffixes would ambiguously direct homelab DNS to work.
      domains = [d for d in work_domains if not any(
        p == d or p.endswith("." + d) or d.endswith("." + p) for p in personal_domains)]
      routes = []
      for family in ("-4", "-6"):
        routes += routes_in(family, {"52"}, NS)
      self.sync_routes(route_plan(routes, protected_routes()))
      self.sync_dns(domains, work_dns)
    elif enabled:
      self.sync_routes(set())
      self.sync_dns([])
    self.snapshot = {"mode": mode, "connected": connected, "backend": backend,
      "at_work": bool(ssids & set(self.office_ssids)), "error": ""}

  def tick(self):
    try:
      self.reconcile()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
      print(str(error), file=sys.stderr, flush=True)
      # Fail closed after losing status, DNS, or location data.
      for cleanup in (lambda: self.sync_routes(set()), lambda: self.sync_dns([]), lambda: tailscale("down")):
        try:
          cleanup()
        except (OSError, ValueError, subprocess.SubprocessError):
          pass
      self.snapshot = {"mode": self.state["mode"], "connected": False, "error": str(error)}


def serve(args):
  controller = Controller(args.default_mode, args.office_ssid, args.resolved)
  Path(SOCKET).unlink(missing_ok=True)
  with socket.socket(socket.AF_UNIX) as server:
    server.bind(SOCKET)
    os.chmod(SOCKET, 0o600)
    os.chown(SOCKET, args.uid, -1)
    server.listen(4)
    server.settimeout(0.25)
    next_tick = 0
    while True:
      if time.monotonic() >= next_tick:
        controller.tick()
        # Connector DNS can introduce fresh S3/CDN routes at any time. Export
        # promptly while connected; office Wi-Fi detection remains ten-second.
        next_tick = time.monotonic() + (1 if controller.snapshot.get("connected") else 10)
      try:
        connection, _ = server.accept()
      except TimeoutError:
        continue
      with connection:
        connection.settimeout(2)
        try:
          _, uid, _ = struct.unpack("3i", connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
          if uid not in (0, args.uid):
            raise ValueError("unauthorized user")
          with connection.makefile("rb") as stream:
            line = stream.readline(4097)
          if len(line) > 4096 or not line.endswith(b"\n"):
            raise ValueError("invalid request")
          request = json.loads(line)
          result = controller.request(request)
          if request["command"] != "status":
            next_tick = 0
        except (OSError, ValueError, KeyError, TypeError) as error:
          result = {"error": str(error)}
        connection.sendall((json.dumps(result) + "\n").encode())


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--serve", action="store_true")
  parser.add_argument("--cleanup", action="store_true")
  parser.add_argument("--uid", type=int)
  parser.add_argument("--default-mode", choices=("off", "auto"), default="off")
  parser.add_argument("--office-ssid", action="append", default=[])
  parser.add_argument("--resolved", action="store_true")
  parser.add_argument("command", nargs="?", choices=("status", "on", "off", "auto", "presence", "login"), default="status")
  parser.add_argument("location", nargs="?", choices=("work", "away"))
  parser.add_argument("--ttl", type=int, default=120)
  args = parser.parse_args()
  if args.cleanup:
    if os.geteuid() != 0:
      parser.error("cleanup requires root")
    controller = Controller(args.default_mode, [], args.resolved)
    for cleanup in (lambda: controller.sync_routes(set()), lambda: controller.sync_dns([]), lambda: tailscale("down")):
      try:
        cleanup()
      except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
    return
  if args.serve:
    serve(args)
    return
  if args.command == "login":
    with socket.socket(socket.AF_UNIX) as client:
      client.settimeout(5)
      client.connect(SOCKET)
      client.sendall(b'{"command":"on"}\n')
      with client.makefile("rb") as stream:
        json.loads(stream.readline(65537))
    # This daemon has one account. `tailscale login` creates an empty profile,
    # discarding OperatorUser before the unprivileged client can authenticate.
    # `up` signs in using the profile prepared by the system service instead.
    hostname = json.loads(tailscale("debug", "prefs")).get("Hostname") or socket.gethostname() + "-work"
    os.execvp("tailscale", ["tailscale", "--socket=" + TS_SOCKET, "up",
      "--hostname=" + hostname, "--operator=joseph",
      "--accept-dns=false", "--accept-routes=true", "--ssh=false", "--netfilter-mode=off"])
  request = {"command": args.command, "location": args.location, "ttl": args.ttl}
  with socket.socket(socket.AF_UNIX) as client:
    client.settimeout(5)
    client.connect(SOCKET)
    client.sendall((json.dumps(request) + "\n").encode())
    with client.makefile("rb") as stream:
      result = json.loads(stream.readline(65537))
  print(json.dumps(result))
  if result.get("error"):
    sys.exit(1)


if __name__ == "__main__":
  main()
