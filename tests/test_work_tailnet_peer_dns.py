from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import socket
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import dns.flags
import dns.message
import dns.query
import dns.rcode
import dns.rrset


SOURCE = Path(__file__).resolve().parents[1] / "nixos/modules/work-tailnet/peer_dns.py"
sys.path.insert(0, str(SOURCE.parent))
spec = importlib.util.spec_from_file_location("work_peer_dns", SOURCE)
peer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(peer)

URL = "http://100.64.165.232:63028/dns-query"


class PeerDnsTests(unittest.TestCase):
  def setUp(self):
    self.root = tempfile.TemporaryDirectory()
    self.addCleanup(self.root.cleanup)
    self.config = Path(self.root.name) / "peer-dns.json"
    self.config.write_text(json.dumps({"app.example": [URL]}))
    config = patch.object(peer, "CONFIG", self.config)
    config.start()
    self.addCleanup(config.stop)
    self.query = dns.message.make_query("app.example", "A")

  def test_longest_suffix_and_removed_policy_never_fall_back(self):
    self.config.write_text(json.dumps({"app.example": [URL], "nested.app.example": ["specific"]}))
    self.assertEqual(peer.upstreams("child.nested.app.example"), ["specific"])
    self.assertEqual(peer.upstreams("other.app.example"), [URL])
    self.assertEqual(peer.upstreams("notapp.example"), [])
    self.config.write_text("{}")
    with patch.object(peer, "exchange") as forward:
      result = dns.message.from_wire(peer.answer(self.query.to_wire()))
      self.assertEqual(result.rcode(), dns.rcode.SERVFAIL)
      forward.assert_not_called()

  def test_upstream_errors_and_wrong_dns_response_fail_closed(self):
    wrong = dns.message.make_response(dns.message.make_query("other.example", "A"))
    for result in [OSError("offline"), ValueError("HTTP 403"), wrong]:
      with self.subTest(result=str(result)), patch.object(peer, "exchange") as forward:
        if isinstance(result, Exception):
          forward.side_effect = result
        else:
          forward.return_value = result
        reply = dns.message.from_wire(peer.answer(self.query.to_wire()))
        self.assertTrue(self.query.is_response(reply))
        self.assertEqual(reply.rcode(), dns.rcode.SERVFAIL)

  def test_udp_truncates_large_dns_reply_but_tcp_retains_records(self):
    reply = dns.message.make_response(self.query)
    reply.answer.append(dns.rrset.from_text("app.example.", 60, "IN", "TXT", '"' + "a" * 200 + '"',
      '"' + "b" * 200 + '"', '"' + "c" * 200 + '"'))
    with patch.object(peer, "exchange", return_value=reply):
      udp = dns.message.from_wire(peer.answer(self.query.to_wire()))
      tcp = dns.message.from_wire(peer.answer(self.query.to_wire(), tcp=True))
    self.assertTrue(udp.flags & dns.flags.TC)
    self.assertFalse(tcp.flags & dns.flags.TC)
    self.assertEqual(len(tcp.answer[0]), 3)

  def test_real_udp_and_tcp_bridge_posts_dns_wire_to_peer_endpoint(self):
    received = []

    class Fixture(BaseHTTPRequestHandler):
      def do_POST(self):
        packet = self.rfile.read(int(self.headers["Content-Length"]))
        received.append((self.path, self.headers["Content-Type"], packet))
        query = dns.message.from_wire(packet)
        response = dns.message.make_response(query)
        response.answer.append(dns.rrset.from_text(query.question[0].name, 60, "IN", "A", "203.0.113.25"))
        body = response.to_wire()
        self.send_response(200)
        self.send_header("Content-Type", "application/dns-message")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

      def log_message(self, *args):
        pass

    with ThreadingHTTPServer(("127.0.0.1", 0), Fixture) as http, \
        peer.UDPServer(("127.0.0.1", 0), peer.UDPHandler) as udp, \
        peer.TCPServer(("127.0.0.1", 0), peer.TCPHandler) as tcp:
      servers = [http, udp, tcp]
      for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
      connect = socket.create_connection

      def peer_connection(address, *args, **kwargs):
        if address == ("100.64.165.232", 63028):
          address = http.server_address
        return connect(address, *args, **kwargs)

      try:
        with patch.object(socket, "create_connection", side_effect=peer_connection):
          for protocol, server in [(dns.query.udp, udp), (dns.query.tcp, tcp)]:
            response = protocol(self.query, "127.0.0.1", port=server.server_address[1], timeout=3)
            self.assertEqual(response.answer[0][0].address, "203.0.113.25")
        self.assertEqual(len(received), 2)
        for path, content_type, packet in received:
          self.assertEqual(path, "/dns-query")
          self.assertEqual(content_type, "application/dns-message")
          self.assertEqual(packet, self.query.to_wire())
      finally:
        for server in servers:
          server.shutdown()


if __name__ == "__main__":
  unittest.main()
