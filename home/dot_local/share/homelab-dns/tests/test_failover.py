"""Exercise the real dnsdist configuration against isolated loopback backends."""
import importlib.util
import json
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("reconcile", ROOT / "reconcile.py")
reconcile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reconcile)


def query(port, name, tcp=False):
    body = b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0"
    message = struct.pack("!6H", 4321, 0x100, 1, 0, 0, 0) + body + struct.pack("!HH", 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM if tcp else socket.SOCK_DGRAM) as sock:
        sock.settimeout(1)
        sock.connect(("127.0.0.1", port))
        if tcp:
            sock.sendall(struct.pack("!H", len(message)) + message)
            size = struct.unpack("!H", sock.recv(2))[0]
            answer = b""
            while len(answer) < size:
                answer += sock.recv(size - len(answer))
        else:
            sock.send(message)
            answer = sock.recv(4096)
    rcode = struct.unpack("!H", answer[2:4])[0] & 15
    count = struct.unpack("!H", answer[6:8])[0]
    return rcode, socket.inet_ntoa(answer[-4:]) if count else None, struct.unpack("!I", answer[-10:-6])[0] if count else None


class Backend:
    def __init__(self, public=False):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.port = self.sock.getsockname()[1]
        self.tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp.bind(("127.0.0.1", self.port))
        self.tcp.listen()
        self.enabled = True
        self.public = public
        self.queries = []
        threading.Thread(target=self.serve, daemon=True).start()
        threading.Thread(target=self.serve_tcp, daemon=True).start()

    def answer(self, data):
        labels, end = [], 12
        while data[end]:
            size = data[end]
            labels.append(data[end + 1:end + size + 1].decode())
            end += size + 1
        name = ".".join(labels)
        if not self.enabled:
            return None
        self.queries.append(name)
        rcode = {"blocked.test": 3, "refused.test": 5, "broken.test": 2}.get(name, 0) if not self.public else 0
        response = data[:2] + struct.pack("!5H", 0x8180 | rcode, 1, int(rcode == 0), 0, 0) + data[12:end + 5]
        if not rcode:
            response += b"\xc0\x0c" + struct.pack("!HHIH", 1, 1, 300, 4) + socket.inet_aton("203.0.113.2" if self.public else "192.0.2.1")
        return response

    def serve_tcp(self):
        while True:
            try:
                client, _ = self.tcp.accept()
                with client:
                    client.settimeout(1)
                    size = struct.unpack('!H', client.recv(2))[0]
                    data = b''
                    while len(data) < size:
                        data += client.recv(size - len(data))
                    response = self.answer(data)
                    if response:
                        client.sendall(struct.pack('!H', len(response)) + response)
            except (OSError, struct.error):
                if self.tcp.fileno() == -1:
                    return

    def serve(self):
        while True:
            try:
                data, address = self.sock.recvfrom(4096)
            except OSError:
                return
            response = self.answer(data)
            if response:
                self.sock.sendto(response, address)


class Failover(unittest.TestCase):
    def test_policy_and_recovery(self):
        home1, home2, public = Backend(), Backend(), Backend(public=True)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            work = path / "work-domains"
            work.write_text("corp.test\n")
            vpn = path / 'vpn-routes.lua'
            vpn.write_text('return {}')
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            config = (ROOT / "dnsdist.conf").read_text()
            config = config.replace('127.0.0.2:53', f'127.0.0.1:{port}')
            config = config.replace('192.168.1.21:53', f'127.0.0.1:{home1.port}')
            config = config.replace('100.99.103.178:53', f'127.0.0.1:{home2.port}')
            start = config.index('for _, address in ipairs({"1.1.1.2:443"')
            end = config.index('\nend', start) + 4
            config = config[:start] + f'newServer({{address="127.0.0.1:{public.port}", pool="fallback", checkInterval=1}})' + config[end:]
            config = config.replace('/var/lib/homelab-dns/work-domains', str(work))
            config = config.replace('/var/lib/homelab-dns/vpn-routes.lua', str(vpn))
            config = config.replace('source=entry.device', 'source="127.0.0.1"')
            config = config.replace('checkInterval=2, checkTimeout=1500, maxCheckFailures=3, rise=2', 'checkInterval=1, checkTimeout=200, maxCheckFailures=2, rise=2')
            conf = path / "dnsdist.conf"
            conf.write_text(config)
            subprocess.run(['dnsdist', '--check-config', '-C', str(conf)], check=True, capture_output=True)
            with (path / "log").open('w+') as log:
                process = subprocess.Popen(['dnsdist', '--supervised', '--disable-syslog', '-C', str(conf)], stdout=log, stderr=log)
                try:
                    def eventually(address):
                        deadline = time.monotonic() + 12
                        while time.monotonic() < deadline:
                            try:
                                if query(port, 'ordinary.test')[1] == address:
                                    return
                            except (OSError, struct.error):
                                pass
                            time.sleep(.2)
                        log.seek(0)
                        self.fail('Routing did not converge: ' + log.read())
                    eventually('192.0.2.1')
                    for name, rcode in [('blocked.test', 3), ('refused.test', 5), ('broken.test', 2)]:
                        self.assertEqual(query(port, name)[0], rcode)
                        self.assertNotIn(name, public.queries)
                    self.assertEqual(query(port, 'ordinary.test', tcp=True)[1], '192.0.2.1')
                    home1.enabled = False
                    time.sleep(3)
                    self.assertEqual(query(port, 'blocked.test')[0], 3)
                    self.assertNotIn('blocked.test', public.queries)
                    home2.enabled = False
                    eventually('203.0.113.2')
                    self.assertEqual(query(port, 'blocked.test'), (0, '203.0.113.2', 1))
                    for name in ['secret.jetersen.dev', 'host.ts.net', 'secret.corp.test', '1.1.168.192.in-addr.arpa']:
                        self.assertIn(query(port, name)[0], [2, 5])
                        self.assertNotIn(name, public.queries)
                    home1.enabled = True
                    eventually('192.0.2.1')
                    public.queries.clear()
                    self.assertEqual(query(port, 'blocked.test')[0], 3)
                    self.assertNotIn('blocked.test', public.queries)
                    # Live plugin route updates take effect without restarting dnsdist.
                    vpn.write_text('return {{device="lo",pool="vpn_test",servers={"127.0.0.1:' + str(public.port) + '"},domains={"corp.test"}}}')
                    time.sleep(2)
                    self.assertEqual(query(port, 'service.corp.test')[1], '203.0.113.2')
                    vpn.write_text('return {}')
                    time.sleep(2)
                    public.queries.clear()
                    self.assertEqual(query(port, 'service.corp.test')[0], 5)
                    self.assertNotIn('service.corp.test', public.queries)
                finally:
                    process.terminate()
                    process.wait(timeout=5)
                    for backend in [home1, home2, public]:
                        backend.sock.close()
                        backend.tcp.close()

    def test_vpn_domain_retention(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'work-domains'
            reconcile.retain_domains(path, {'corp.test'})
            reconcile.retain_domains(path, set())
            self.assertEqual(path.read_text(), 'corp.test\n')


if __name__ == '__main__':
    unittest.main()
