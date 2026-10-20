"""Exercise the production Lua with real dnsdist and isolated loopback backends."""
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time

import dns.message
import dns.query
import dns.rcode
import dns.rrset

START = time.monotonic()
PEER = "rocket.rockhopper-bleak.ts.net."
SUFFIX = "rockhopper-bleak.ts.net."
PROBE = "dns.technitium.lan.jetersen.dev."
GRAFANA = "grafana.moviestarplanet.tech."


class Backend:
    def __init__(self, port, answer, magic=False):
        self.port, self.answer, self.magic = port, answer, magic
        self.queries = []
        self.lock = threading.Lock()
        self.start()

    def start(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", self.port))
        self.sock.settimeout(0.1)
        self.running = True
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def stop(self):
        self.running = False
        self.thread.join(timeout=2)
        assert not self.thread.is_alive()
        self.sock.close()

    def count(self, name):
        with self.lock:
            return self.queries.count(name)

    def serve(self):
        while self.running:
            try:
                wire, addr = self.sock.recvfrom(65535)
            except socket.timeout:
                continue
            q = dns.message.from_wire(wire)
            name = q.question[0].name.to_text()
            with self.lock:
                self.queries.append(name)
            r = dns.message.make_response(q)
            code = {"nx.example.": 3, "refused.example.": 5, "fail.example.": 2}.get(name, 0)
            if self.magic and name == SUFFIX:
                code = 2
            if code:
                r.set_rcode(code)
            else:
                r.answer.append(dns.rrset.from_text(name, 300, "IN", "A", self.answer))
            self.sock.sendto(r.to_wire(), addr)


def query(name, port=15353):
    return dns.query.udp(dns.message.make_query(name, "A"), "127.0.0.1", port=port, timeout=0.4)


def address(response):
    return response.answer[0][0].address if response.answer else None


def wait(label, predicate, seconds=20):
    deadline = time.monotonic() + seconds
    last = None
    while time.monotonic() < deadline:
        for proc in processes:
            assert proc.poll() is None, f"dnsdist exited: {proc.returncode}"
        try:
            if predicate():
                print(f"{time.monotonic() - START:.2f}s: {label}", flush=True)
                return
        except (dns.exception.Timeout, ConnectionError, OSError) as exc:
            last = exc
        time.sleep(0.1)
    raise AssertionError(f"timeout waiting for {label}: {last}")


def write(name, text):
    # Rename mirrors the bridge's atomic publication, including live route reloads.
    path = Path(name)
    path.with_suffix(".tmp").write_text(text)
    path.with_suffix(".tmp").replace(path)


def wait_for_consistent_answers(label, name, expected, count=8):
    consecutive = 0

    def ready():
        nonlocal consecutive
        try:
            correct = address(query(name)) == expected
        except (dns.exception.Timeout, ConnectionError, OSError):
            correct = False
        consecutive = consecutive + 1 if correct else 0
        return consecutive >= count

    wait(label, ready)


def spawn(name, config):
    Path(name + ".conf").write_text(config)
    log = open(name + ".log", "w")
    proc = subprocess.Popen(["dnsdist", "--supervised", "--disable-syslog", "-C", name + ".conf"],
                            stdout=log, stderr=subprocess.STDOUT)
    processes.append(proc)
    return proc


processes = []
backends = []
try:
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                    "-subj", "/CN=fallback.test", "-addext", "subjectAltName=DNS:fallback.test",
                    "-keyout", "key.pem", "-out", "cert.pem"], check=True, capture_output=True)
    root = str(Path.cwd())
    for port, ip, magic in [(15354, "100.64.0.7", True), (15355, "192.0.2.1", False),
                             (15356, "192.0.2.2", False), (15357, "192.0.2.3", False),
                             (15358, "192.0.2.4", False)]:
        backends.append(Backend(port, ip, magic))
    magic, cluster, nas, public, vpn = backends
    assert query(PEER, 15354).rcode() == 0
    assert query(SUFFIX, 15354).rcode() == dns.rcode.SERVFAIL
    spawn("doh", f'''
setSecurityPollSuffix("")
setLocal("127.0.0.1:15359")
setACL({{"127.0.0.0/8"}})
addDOHLocal("127.0.0.1:15443", "{root}/cert.pem", "{root}/key.pem", {{"/dns-query"}})
newServer({{address="127.0.0.1:15357", healthCheckMode="up"}})
''')
    write("work-domains", "corp.test.\nmoviestarplanet.tech.\nprivate.moviestarplanet.tech.\nmoviestarplanet.tech.corp.test.\n")
    write("vpn-routes.lua", "return {}")
    spawn("production", f'''
setSecurityPollSuffix("")
homelabDnsEndpoints = {{listen="127.0.0.1:15353", magic="127.0.0.1:15354",
cluster="127.0.0.1:15355", nas="127.0.0.1:15356", fallback={{"127.0.0.1:15443"}},
fallbackName="fallback.test", caStore="{root}/cert.pem", stateDirectory="{root}"}}
dofile("{sys.argv[1]}")
''')
    wait("home preferred", lambda: address(query("public.example.")) in {cluster.answer, nas.answer})
    # Observe three health checks in addition to the two direct fixture queries.
    # A bare-suffix probe must mark MagicDNS down before the routed peer query.
    wait("MagicDNS health checks completed", lambda: magic.count(PEER) + magic.count(SUFFIX) >= 5, 20)
    assert address(query(PEER)) == magic.answer, "MagicDNS peer health/routing failed"
    assert query(SUFFIX).rcode() == dns.rcode.SERVFAIL
    assert address(query("www.ts.net.")) in {cluster.answer, nas.answer}
    assert public.count("www.ts.net.") == 0
    assert public.count("public.example.") == 0
    for name, code in [("nx.example.", 3), ("refused.example.", 5), ("fail.example.", 2)]:
        assert query(name).rcode() == code
        assert public.count(name) == 0, f"public retry of {name}"
    assert query("host.corp.test.").rcode() == dns.rcode.REFUSED
    assert address(query(GRAFANA)) in {cluster.answer, nas.answer}
    assert address(query("moviestarplanet.tech.")) in {cluster.answer, nas.answer}
    assert address(query("host.private.moviestarplanet.tech.")) in {cluster.answer, nas.answer}
    assert query("moviestarplanet.tech.corp.test.").rcode() == dns.rcode.REFUSED
    assert public.count(GRAFANA) == 0
    write("vpn-routes.lua", 'return {{pool="vpn-test", servers={"127.0.0.1:15358"}, domains={"corp.test.", "moviestarplanet.tech."}}}')
    wait("dynamic VPN route active", lambda: address(query("host.corp.test.")) == vpn.answer)
    assert address(query(GRAFANA)) == vpn.answer
    write("vpn-routes.lua", "return {}")
    wait("removed VPN route fails closed", lambda: query("host.corp.test.").rcode() == dns.rcode.REFUSED)
    assert address(query(GRAFANA)) in {cluster.answer, nas.answer}
    cluster.stop()
    wait_for_consistent_answers("remaining home backend consistently serves after cluster stops",
                                "single.example.", nas.answer)
    nas.stop()
    wait("home outage uses verified local DoH", lambda: address(query("outage.example.")) == public.answer)
    assert address(query(GRAFANA)) == public.answer
    response = query("ttl.example.")
    assert address(response) == public.answer
    assert all(rr.ttl <= 1 for rr in response.answer), response
    for name in ["private.jetersen.dev.", "www.ts.net.", "1.0.0.10.in-addr.arpa.", "0.ip6.arpa."]:
        assert query(name).rcode() == dns.rcode.SERVFAIL, name
        assert public.count(name) == 0, f"private name leaked: {name}"
    assert query("host.corp.test.").rcode() == dns.rcode.REFUSED
    assert public.count("host.corp.test.") == 0
    cluster.start()
    nas.start()
    wait("home recovers after backend restart", lambda: address(query("recovered.example.")) in {cluster.answer, nas.answer})
    assert address(query("after-recovery.example.")) in {cluster.answer, nas.answer}
    assert public.count("after-recovery.example.") == 0
    assert magic.count(PEER) >= 3
    assert cluster.count(PROBE) >= 2 and nas.count(PROBE) >= 2
    print(f"PASS production DNS integration ({time.monotonic() - START:.2f}s)", flush=True)
finally:
    for proc in processes:
        proc.terminate()
    for proc in processes:
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    for backend in backends:
        if backend.running:
            backend.stop()
    if sys.exc_info()[0]:
        for log in Path.cwd().glob("*.log"):
            print(f"--- {log} ---\n{log.read_text()}", file=sys.stderr)
