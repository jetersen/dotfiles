"""Synthetic NM D-Bus snapshots and loopback-only DNS; no portal traffic."""
import importlib.util
from pathlib import Path
import socket
import socketserver
import struct
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import dns.flags
import dns.message
import dns.rcode
import dns.rrset

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('portal', ROOT / 'nixos/modules/portal-dns.py')
portal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portal)


class PortalTests(unittest.TestCase):
  def setUp(self):
    self.data = {
      (portal.ROOT, portal.NM): {'PrimaryConnection': '/active/1', 'ConnectivityCheckEnabled': True},
      ('/active/1', portal.NM + '.Connection.Active'): {'Type': '802-11-wireless', 'Devices': ['/device/1']},
      ('/device/1', portal.NM + '.Device'): {
        'State': 100, 'IpInterface': 'wlan0', 'Ip4Config': '/ip4/1', 'Ip6Config': '/ip6/1',
        'Ip4Connectivity': 2, 'Ip6Connectivity': 3},
      ('/ip4/1', portal.NM + '.IP4Config'): {'NameserverData': [{'address': '192.0.2.53'}]},
      ('/ip6/1', portal.NM + '.IP6Config'): {'Nameservers': [bytes.fromhex('fe800000000000000000000000000054')]},
    }
    self.get = lambda path, interface: self.data[(path, interface)]
    self.device = self.data[('/device/1', portal.NM + '.Device')]

  def test_portal_full_recurrence_dhcp_hotspot_and_offline(self):
    with tempfile.TemporaryDirectory() as root:
      lease = Path(root) / 'lease'
      self.assertEqual(portal.update(self.get, lease=lease)[1:],
                       ('wlan0', ('192.0.2.53', 'fe80::54'), True))
      self.assertGreater(int(lease.read_text()), time.time())
      self.device['Ip4Connectivity'] = 4
      self.assertFalse(portal.update(self.get, lease=lease)[3])
      self.assertEqual(lease.read_text(), '0')
      # Reauthentication restores underlay without a service restart.
      self.device['Ip4Connectivity'] = 2
      self.assertTrue(portal.update(self.get, lease=lease)[3])
      self.data[('/ip4/1', portal.NM + '.IP4Config')]['NameserverData'] = [{'address': '198.51.100.1'}]
      self.device['Ip6Config'] = '/'
      self.device['IpInterface'] = 'hotspot0'
      self.assertEqual(portal.update(self.get, lease=lease)[1:], ('hotspot0', ('198.51.100.1',), True))
      self.device['State'] = 30
      self.assertEqual(portal.update(self.get, lease=lease)[1:], ('', (), False))
      self.device['State'] = 100
      self.assertTrue(portal.update(self.get, lease=lease)[3])

  def test_vpn_global_full_does_not_hide_underlay_portal(self):
    self.data[(portal.ROOT, portal.NM)]['Connectivity'] = 4
    self.assertTrue(portal.read_network(self.get)[2])
    self.data[('/active/1', portal.NM + '.Connection.Active')]['Type'] = 'vpn'
    self.assertEqual(portal.read_network(self.get), ('', (), False))

  def test_disabled_check_does_not_enable_indefinite_bypass(self):
    self.data[(portal.ROOT, portal.NM)]['ConnectivityCheckEnabled'] = False
    self.assertFalse(portal.read_network(self.get)[2])

  def test_resolvers_reject_recursion_and_private_tailnets(self):
    self.assertEqual(portal.servers(['127.0.0.2', '127.0.0.3', '100.100.100.100',
      '100.88.1.2', 'fd7a:115c:a1e0::1', '::', 'ff02::1', 'invalid',
      '192.168.1.1', 'fe80::1', '192.168.1.1']), ('192.168.1.1', 'fe80::1'))

  def test_private_and_work_names_never_forward(self):
    with tempfile.TemporaryDirectory() as root:
      work = Path(root) / 'domains'
      work.write_text('corp.example\n')
      for name in ('host.ts.net', 'host.jetersen.dev', '1.0.0.10.in-addr.arpa',
                   '0.ip6.arpa', 'HOST.CORP.EXAMPLE.', 'corp.example'):
        self.assertFalse(portal.permitted(name, True, work), name)
      self.assertTrue(portal.permitted('login.hotel', True, work))
      self.assertFalse(portal.permitted('public.example', False, work))
      self.assertTrue(portal.permitted(portal.PROBE, False, work))

  def test_expired_state_policy_change_and_network_change_discard_answers(self):
    q = dns.message.make_query('public.example', 'A')
    reply = dns.message.make_response(q)
    reply.answer.append(dns.rrset.from_text('public.example.', 300, 'IN', 'A', '192.0.2.1'))
    with patch.object(portal, 'exchange', return_value=reply) as exchange:
      portal.SNAPSHOT = (time.monotonic() - 6, 'wlan0', ('192.0.2.53',), True)
      self.assertEqual(dns.message.from_wire(portal.answer(q.to_wire())).rcode(), 2)
      exchange.assert_not_called()
      portal.SNAPSHOT = (time.monotonic(), 'wlan0', ('192.0.2.53',), True)
      self.assertEqual(dns.message.from_wire(portal.answer(q.to_wire())).answer[0].ttl, 1)
      def change(*args):
        portal.SNAPSHOT = (time.monotonic(), 'wlan1', ('198.51.100.53',), True)
        return reply
      exchange.side_effect = change
      self.assertEqual(dns.message.from_wire(portal.answer(q.to_wire())).rcode(), 2)

  def test_real_udp_truncation_tcp_and_link_binding(self):
    class Handler(socketserver.BaseRequestHandler):
      def handle(self):
        if isinstance(self.request, tuple):
          packet, sock = self.request
          q = dns.message.from_wire(packet)
          r = dns.message.make_response(q)
          r.flags |= dns.flags.TC
          sock.sendto(r.to_wire(), self.client_address)
        else:
          header = self.request.recv(2)
          size, = struct.unpack('!H', header)
          packet = self.request.recv(size)
          q = dns.message.from_wire(packet)
          r = dns.message.make_response(q)
          r.answer.append(dns.rrset.from_text(q.question[0].name, 100, 'IN', 'A', '192.0.2.1'))
          packet = r.to_wire()
          self.request.sendall(struct.pack('!H', len(packet)) + packet)
    for family, address in ((socket.AF_INET, '127.0.0.1'), (socket.AF_INET6, '::1')):
      class TCP(socketserver.TCPServer):
        address_family = family
      class UDP(socketserver.UDPServer):
        address_family = family
      with TCP((address, 0), Handler) as tcp:
        port = tcp.server_address[1]
        with UDP((address, port), Handler) as udp:
          for server in (tcp, udp):
            threading.Thread(target=server.serve_forever, daemon=True).start()
          try:
            for stream in (False, True):
              r = portal.exchange(dns.message.make_query('test.example', 'A'), 'lo', (address,), stream, port)
              self.assertEqual(r.answer[0][0].address, '192.0.2.1')
          finally:
            tcp.shutdown()
            udp.shutdown()
