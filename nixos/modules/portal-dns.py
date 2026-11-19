"""Framework's underlay DNS bridge; never owns resolv.conf or VPN state.

NetworkManager's HTTP check binds to the device but dns=none uses host DNS.
Only its check hostname bypasses normal policy once connectivity is FULL.
"""
import ipaddress
import logging
from pathlib import Path
import socket
import socketserver
import struct
import threading
import time

import dns.exception
import dns.message
import dns.query
import dns.rcode

NM = 'org.freedesktop.NetworkManager'
ROOT = '/org/freedesktop/NetworkManager'
PROBE = 'nmcheck.gnome.org'
LEASE = Path('/run/homelab-portal/lease')
WORK = Path('/run/work-tailnet/domains')
PRIVATE = ('jetersen.dev', 'ts.net', 'in-addr.arpa', 'ip6.arpa')
LOCK = threading.Lock()
SNAPSHOT = (0, '', (), False)


def servers(values):
  result = []
  for value in values:
    try:
      address = ipaddress.ip_address(value)
      if (address.is_unspecified or address.is_loopback or address.is_multicast
          or address in ipaddress.ip_network('100.64.0.0/10')
          or address in ipaddress.ip_network('fd7a:115c:a1e0::/48')):
        continue
      result.append(str(address))
    except ValueError:
      continue
  return tuple(dict.fromkeys(result))


def read_network(get):
  """Use NM's primary *underlay*, not global connectivity (VPN may be FULL)."""
  manager = get(ROOT, NM)
  primary = manager['PrimaryConnection']
  if primary == '/':
    return '', (), False
  active = get(primary, NM + '.Connection.Active')
  if active['Type'] not in ('802-11-wireless', '802-3-ethernet', 'gsm'):
    return '', (), False
  for path in active['Devices']:
    device = get(path, NM + '.Device')
    if device['State'] != 100:
      continue
    values, states = [], []
    for family in (4, 6):
      config = device[f'Ip{family}Config']
      if config == '/':
        continue
      ip = get(config, NM + f'.IP{family}Config')
      if family == 4:
        addresses = [entry['address'] for entry in ip['NameserverData']]
      else:
        addresses = [str(ipaddress.ip_address(bytes(entry))) for entry in ip['Nameservers']]
      values.extend(addresses)
      states.append(int(device[f'Ip{family}Connectivity']))
    if get(ROOT, NM)['PrimaryConnection'] != primary:
      return '', (), False
    # NM FULL=4 requires its configured response/header, not merely any HTTP 200.
    return str(device['IpInterface']), servers(values), (
      bool(manager['ConnectivityCheckEnabled']) and 4 not in states)
  return '', (), False


def update(get, now=None, lease=LEASE):
  global SNAPSHOT
  now = time.monotonic() if now is None else now
  interface, addresses, portal = read_network(get)
  snapshot = (now, interface, addresses, bool(addresses) and portal)
  with LOCK:
    SNAPSHOT = snapshot
  # Lua uses wall-clock expiry; the forwarding path uses monotonic time too.
  temporary = lease.with_suffix('.tmp')
  temporary.write_text(str(int(time.time()) + 5) if snapshot[3] else '0')
  temporary.chmod(0o644)
  temporary.replace(lease)
  return snapshot


def permitted(name, portal, work=WORK):
  try:
    domains = (*PRIVATE, *work.read_text().splitlines())
  except FileNotFoundError:
    domains = PRIVATE
  name = name.rstrip('.').lower()
  if any(name == d.rstrip('.').lower() or name.endswith('.' + d.rstrip('.').lower())
         for d in domains if d):
    return False
  return portal or name == PROBE


def exchange(query, interface, addresses, tcp=False, port=53):
  for address in addresses:
    family = socket.AF_INET6 if ':' in address else socket.AF_INET
    destination = address
    if family == socket.AF_INET6 and ipaddress.ip_address(address).is_link_local:
      destination += '%' + interface
    try:
      def ask(stream):
        with socket.socket(family, socket.SOCK_STREAM if stream else socket.SOCK_DGRAM) as sock:
          sock.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, interface.encode() + b'\0')
          if stream:
            sock.settimeout(1)
            sock.connect((destination, port))
          sock.setblocking(False)
          if stream:
            return dns.query.tcp(query, destination, timeout=1, sock=sock)
          return dns.query.udp(query, destination, port=port, timeout=1, sock=sock)
      reply = ask(tcp)
      if not tcp and reply.flags & 0x0200:
        reply = ask(True)
      if reply.rcode() != dns.rcode.SERVFAIL:
        return reply
    except (OSError, dns.exception.DNSException):
      continue
  raise OSError('No underlay DNS response')


def answer(packet, tcp=False):
  query = dns.message.from_wire(packet)
  reply = dns.message.make_response(query)
  reply.set_rcode(dns.rcode.SERVFAIL)
  with LOCK:
    snapshot = SNAPSHOT
  stamp, interface, addresses, portal = snapshot
  try:
    if (time.monotonic() - stamp <= 5 and interface and addresses and len(query.question) == 1
        and not query.flags & 0x8000 and query.opcode() == 0
        and permitted(query.question[0].name.to_text(), portal)):
      candidate = exchange(query, interface, addresses, tcp)
      with LOCK:
        current = SNAPSHOT
      if current[1:] == snapshot[1:] and time.monotonic() - current[0] <= 5:
        reply = candidate
        # Do not retain portal answers after the link or policy changes.
        for section in (reply.answer, reply.authority, reply.additional):
          for rrset in section:
            rrset.ttl = min(rrset.ttl, 1)
  except (OSError, ValueError, dns.exception.DNSException):
    pass
  return reply.to_wire(max_size=65535 if tcp else min(max(query.payload, 512), 4096),
                       prefer_truncation=True)


class UDPHandler(socketserver.BaseRequestHandler):
  def handle(self):
    packet, stream = self.request
    try:
      stream.sendto(answer(packet), self.client_address)
    except (ValueError, dns.exception.DNSException):
      pass


class TCPHandler(socketserver.StreamRequestHandler):
  timeout = 5

  def handle(self):
    try:
      while header := self.rfile.read(2):
        if len(header) != 2:
          return
        size, = struct.unpack('!H', header)
        packet = self.rfile.read(size)
        if len(packet) != size:
          return
        reply = answer(packet, True)
        self.wfile.write(struct.pack('!H', len(reply)) + reply)
        self.wfile.flush()
    except (OSError, ValueError, dns.exception.DNSException):
      pass


class Threads(socketserver.ThreadingMixIn):
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


class UDPServer(Threads, socketserver.UDPServer):
  pass


class TCPServer(Threads, socketserver.TCPServer):
  allow_reuse_address = True


def main():
  import dbus

  logging.basicConfig(level=logging.INFO, format='%(message)s')
  bus = dbus.SystemBus()

  def get(path, interface):
    return dbus.Interface(bus.get_object(NM, path), 'org.freedesktop.DBus.Properties').GetAll(interface, timeout=2)

  def refresh():
    global SNAPSHOT
    previous = None
    while True:
      try:
        snapshot = update(get)
        status = snapshot[1:]
        if status != previous:
          logging.info('underlay=%s resolvers=%d portal=%s', snapshot[1] or 'offline',
                       len(snapshot[2]), snapshot[3])
        previous = status
      except (dbus.DBusException, OSError, KeyError, ValueError) as error:
        if previous != 'error':
          logging.warning('NetworkManager snapshot unavailable: %s', error)
        previous = 'error'
        with LOCK:
          SNAPSHOT = (0, '', (), False)
        LEASE.write_text('0')
      time.sleep(1)

  threading.Thread(target=refresh, daemon=True).start()
  with UDPServer(('127.0.0.1', 5355), UDPHandler) as udp, TCPServer(('127.0.0.1', 5355), TCPHandler) as tcp:
    threading.Thread(target=tcp.serve_forever, daemon=True).start()
    udp.serve_forever()


if __name__ == '__main__':
  main()
