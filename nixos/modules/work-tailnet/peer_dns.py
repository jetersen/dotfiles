"""Loopback DNS-to-HTTP bridge for app connectors in the work namespace."""

import http.client
import ipaddress
import json
from pathlib import Path
import socketserver
import struct
import threading
import time

import dns.exception
import dns.flags
import dns.message
import dns.opcode
import dns.rcode
import dns.rdatatype

from control import peer_doh_url

CONFIG = Path("/run/work-tailnet/peer-dns.json")
ROUTES = Path("/run/work-tailnet/exported-routes.json")


def upstreams(name):
  # Re-read the atomically replaced policy on each request, including Off.
  routes = json.loads(CONFIG.read_text())
  matches = [domain for domain in routes if name == domain or name.endswith("." + domain)]
  return routes[max(matches, key=len)] if matches else []


def exchange(packet, address):
  endpoint = peer_doh_url(address)
  connection = http.client.HTTPConnection(endpoint.hostname, endpoint.port, timeout=4)
  try:
    # Literal tailnet IPs, no environment proxy, redirects or bootstrap DNS.
    connection.request("POST", endpoint.path, packet,
      {"Content-Type": "application/dns-message", "Accept": "application/dns-message"})
    response = connection.getresponse()
    body = response.read(65536)
    if (response.status != 200 or response.getheader("Content-Type") != "application/dns-message"
        or len(body) > 65535):
      raise ValueError("Invalid peer DNS response")
    return dns.message.from_wire(body)
  finally:
    connection.close()


def wait_for_routes(reply, timeout=3):
  addresses = [ipaddress.ip_address(record.address) for rrset in reply.answer
    if rrset.rdtype in (dns.rdatatype.A, dns.rdatatype.AAAA) for record in rrset]
  if not addresses:
    return True
  deadline = time.monotonic() + timeout
  while True:
    try:
      routes = [ipaddress.ip_network(prefix) for prefix in json.loads(ROUTES.read_text())]
      if all(any(address.version == route.version and address in route for route in routes) for address in addresses):
        return True
    except (OSError, ValueError):
      pass
    if time.monotonic() >= deadline:
      return False
    time.sleep(0.05)


def answer(packet, tcp=False):
  query = dns.message.from_wire(packet)
  if query.flags & dns.flags.QR:
    raise ValueError("Expected a DNS query")
  response = dns.message.make_response(query)
  response.set_rcode(dns.rcode.SERVFAIL)
  if len(query.question) == 1 and query.opcode() == dns.opcode.QUERY:
    name = query.question[0].name.to_text().rstrip(".").lower()
    try:
      for address in upstreams(name):
        try:
          reply = exchange(packet, address)
          if not query.is_response(reply):
            raise ValueError("Mismatched peer DNS response")
          if reply.rcode() == dns.rcode.SERVFAIL:
            continue
          if not wait_for_routes(reply):
            raise ValueError("Connector routes are not ready")
          response = reply
          break
        except (OSError, ValueError, http.client.HTTPException, dns.exception.DNSException):
          continue
    except (OSError, ValueError):
      pass
  limit = 65535 if tcp else min(max(query.payload, 512), 4096)
  return response.to_wire(max_size=limit, prefer_truncation=True)


class UDPHandler(socketserver.BaseRequestHandler):
  def handle(self):
    packet, stream = self.request
    try:
      stream.sendto(answer(packet), self.client_address)
    except (OSError, ValueError, dns.exception.DNSException):
      pass


class TCPHandler(socketserver.StreamRequestHandler):
  timeout = 5

  def handle(self):
    try:
      while header := self.rfile.read(2):
        if len(header) != 2:
          return
        size, = struct.unpack("!H", header)
        packet = self.rfile.read(size)
        if len(packet) != size:
          return
        reply = answer(packet, tcp=True)
        self.wfile.write(struct.pack("!H", len(reply)) + reply)
        self.wfile.flush()
    except (OSError, ValueError, dns.exception.DNSException):
      pass


class BoundedThreads(socketserver.ThreadingMixIn):
  daemon_threads = True
  slots = threading.BoundedSemaphore(32)

  def process_request(self, request, address):
    if not self.slots.acquire(blocking=False):
      self.shutdown_request(request)
      return
    try:
      super().process_request(request, address)
    except Exception:
      self.slots.release()
      raise

  def process_request_thread(self, request, address):
    try:
      super().process_request_thread(request, address)
    finally:
      self.slots.release()


class UDPServer(BoundedThreads, socketserver.UDPServer):
  pass


class TCPServer(BoundedThreads, socketserver.TCPServer):
  allow_reuse_address = True


def main():
  with UDPServer(("127.0.0.1", 5354), UDPHandler) as udp, TCPServer(("127.0.0.1", 5354), TCPHandler) as tcp:
    threading.Thread(target=tcp.serve_forever, daemon=True).start()
    udp.serve_forever()


if __name__ == "__main__":
  main()
