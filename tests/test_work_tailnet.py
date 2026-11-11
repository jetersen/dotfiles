import importlib.util
import ipaddress
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "nixos/modules/work-tailnet/control.py"
spec = importlib.util.spec_from_file_location("work_tailnet", SOURCE)
work = importlib.util.module_from_spec(spec)
spec.loader.exec_module(work)


class WorkTailnetTests(unittest.TestCase):
  def test_on_restores_saved_work_profile_without_creating_a_new_one(self):
    profiles = [{"id": "existing-work", "tailnet": "example.work", "selected": False}]
    with patch.object(work, "tailscale", return_value=json.dumps(profiles)), patch.object(work, "local_request") as api:
      self.assertTrue(work.restore_work_profile({"profileId": "existing-work"}))
      api.assert_called_once_with("POST", "/localapi/v0/profiles/existing-work", expected=204)
    profiles[0]["selected"] = True
    with patch.object(work, "tailscale", return_value=json.dumps(profiles)), patch.object(work, "local_request") as api:
      self.assertFalse(work.restore_work_profile({"profileId": "existing-work"}))
      api.assert_not_called()
    with patch.object(work, "tailscale", return_value="[]"), patch.object(work, "local_request") as api:
      self.assertFalse(work.restore_work_profile({"profileId": "existing-work"}))
      api.assert_not_called()

  def test_tailnet_display_name_comes_from_the_isolated_daemon(self):
    for selected in (True, False):
      with patch.object(work, "tailscale", return_value=json.dumps([{"id": "work", "selected": selected, "tailnet": "example.work"}])) as ts:
        self.assertEqual(work.profile_info(), {"hasProfile": True, "tailnetName": "example.work"})
        ts.assert_called_once_with("switch", "--list", "--json")
    with patch.object(work, "tailscale", return_value="[]"):
      self.assertEqual(work.profile_info(), {"hasProfile": False, "tailnetName": ""})
    with patch.object(work, "tailscale", side_effect=OSError("unavailable")):
      self.assertEqual(work.profile_info(), {"hasProfile": None, "tailnetName": ""})

  def test_tailnet_is_learned_once_and_personal_and_other_accounts_are_rejected(self):
    current = {"StableID": "work-id", "Name": "example.work"}
    personal = {"StableID": "personal-id", "Name": "personal.example"}
    profiles = [{"id": "local-profile", "selected": True}]
    with tempfile.TemporaryDirectory() as root, patch.object(work, "tailscale", return_value=json.dumps(profiles)):
      path = Path(root) / "tailnet.json"
      with self.assertRaises(ValueError):
        work.remember_work_tailnet(path, personal, personal)
      self.assertFalse(path.exists())
      with self.assertRaises(ValueError):
        work.remember_work_tailnet(path, current, {})
      saved = work.remember_work_tailnet(path, current, personal)
      self.assertEqual(saved["id"], "work-id")
      self.assertEqual(saved["profileId"], "local-profile")
      self.assertEqual(work.remember_work_tailnet(path, current | {"Name": "renamed.example"}, personal), saved)
      with self.assertRaises(ValueError):
        work.remember_work_tailnet(path, {"StableID": "different-id"}, personal)
      self.assertEqual(json.loads(path.read_text()), saved)

  def test_manual_choice_overrides_presence_and_wifi(self):
    presence = {"at_work": True, "expires": 200}
    self.assertFalse(work.wanted("off", {"MSP"}, ["MSP"], presence, 100))
    self.assertTrue(work.wanted("on", set(), [], {}, 100))

  def test_only_active_office_wifi_or_fresh_presence_connects(self):
    self.assertTrue(work.wanted("auto", {"MSP"}, ["MSP"], {}, 100))
    self.assertFalse(work.wanted("auto", {"Home"}, ["MSP"], {}, 100))
    self.assertTrue(work.wanted("auto", set(), [], {"at_work": True, "expires": 101}, 100))
    self.assertFalse(work.wanted("auto", set(), [], {"at_work": True, "expires": 100}, 100))
    self.assertFalse(work.wanted("auto", set(), [], {"at_work": False, "expires": 200}, 100))

  def test_real_routes_exclude_defaults_magicdns_lan_and_personal_peers(self):
    routes = [{"dst": p, "dev": "tailscale-work"} for p in
      ["100.64.0.0/10", "192.168.1.0/24", "10.20.0.0/16", "fd7a:115c:a1e0::/48", "default", "::/0"]]
    routes += [{"dst": "10.30.0.0/16", "dev": "wt-peer"},
      {"dst": "10.40.0.0/16", "type": "throw"}]
    protected = list(map(ipaddress.ip_network,
      ["100.100.100.100/32", "100.99.130.103/32", "192.168.1.0/24", "fd7a:115c:a1e0::1/128"]))
    result = list(map(ipaddress.ip_network, work.route_plan(routes, protected)))
    for reserved in protected:
      self.assertFalse(any(n.overlaps(reserved) for n in result if n.version == reserved.version))
    for allowed in ["100.98.179.109", "10.20.1.2", "fd7a:115c:a1e0::2"]:
      addr = ipaddress.ip_address(allowed)
      self.assertTrue(any(addr in n for n in result if addr.version == n.version))
    self.assertFalse(any(n.prefixlen == 0 for n in result))
    self.assertNotIn(ipaddress.ip_network("10.30.0.0/16"), result)

  def test_entire_personal_pool_is_reserved_for_future_nodes(self):
    with patch.object(work, "routes_in", return_value=[]):
      protected = work.protected_routes()
    self.assertIn(ipaddress.ip_network("100.99.0.0/16"), protected)
    self.assertEqual(work.route_plan([{"dst": "100.99.10.1/32", "dev": "tailscale-work"}], protected), set())

  def test_empty_table_and_normalized_host_routes_are_idempotent(self):
    def kernel(*args):
      self.assertEqual(args[-2:], ("table", "all"))
      return json.dumps([{"dst": "10.20.1.1", "table": "53", "metrics": [{"mtu": 1280}]}]) if "-4" in args else "[]"
    with tempfile.TemporaryDirectory() as root, patch.object(work, "RUN", Path(root)), \
        patch.object(work, "run", side_effect=kernel) as commands:
      controller = self.controller(root)
      controller.sync_routes({"10.20.1.1/32"})
      self.assertEqual(commands.call_count, 2)  # No add/delete for an unchanged host route.
      self.assertEqual(json.loads((Path(root) / "exported-routes.json").read_text()), ["10.20.1.1/32"])
      self.assertEqual(work.routes_in("-6", {"53"}), [])

  def test_application_mtu_is_constrained_on_routes_and_repairs_existing_routes(self):
    with tempfile.TemporaryDirectory() as root, patch.object(work, "RUN", Path(root)), \
        patch.object(work, "routes_in", side_effect=[[{"dst": "203.0.113.25", "metrics": [{"mtu": 1500}]}], []]), \
        patch.object(work, "run") as run:
      self.controller(root).sync_routes({"203.0.113.25/32", "2001:db8::25/128"})
      self.assertEqual(run.call_count, 2)
      for call in run.call_args_list:
        self.assertEqual(call.args[-4:], ("table", "53", "mtu", "1280"))

  def test_route_receipt_is_published_only_after_success_and_cleared_when_off(self):
    with tempfile.TemporaryDirectory() as root, patch.object(work, "RUN", Path(root)), \
        patch.object(work, "routes_in", return_value=[]), patch.object(work, "run") as run:
      controller = self.controller(root)
      receipt = Path(root) / "exported-routes.json"
      run.side_effect = OSError("route installation failed")
      with self.assertRaises(OSError):
        controller.sync_routes({"203.0.113.25/32"})
      self.assertFalse(receipt.exists())
      run.side_effect = None
      controller.sync_routes({"203.0.113.25/32"})
      self.assertEqual(json.loads(receipt.read_text()), ["203.0.113.25/32"])
      controller.sync_routes(set())
      self.assertEqual(json.loads(receipt.read_text()), [])

  def test_domains_are_validated_and_root_is_rejected(self):
    self.assertEqual(work.valid_domains({"CurrentTailnet": {"MagicDNSSuffix": "work.ts.net"},
      "SplitDNSRoutes": {"corp.example.": [], ".": [], "bad\nname": [], "a..b": [],
        "a" * 64 + ".test": []}}), ["corp.example", "work.ts.net"])

  def test_split_dns_uses_own_resolver_and_excludes_personal_domains(self):
    dns = {"SplitDNSRoutes": {"corp.example.": [{"Addr": "100.65.1.1"}],
      "jetersen.dev": [{"Addr": "100.65.1.2"}]}}
    self.assertEqual(work.dns_plan(["corp.example", "work.ts.net"], dns),
      ("server=/corp.example/100.65.1.1\n", {}))
    dns["SplitDNSRoutes"]["corp.example."] = [{"Addr": "100.65.1.1\nserver=1.1.1.1"}]
    with self.assertRaises(ValueError):
      work.dns_plan(["corp.example"], dns)

  def test_app_connector_urls_use_bridge_and_preserve_ipv4_ipv6_endpoints(self):
    urls = ["http://100.64.165.232:63028/dns-query",
      "http://[fd7a:115c:a1e0::a332:a419]:63029/dns-query"]
    dns = {"SplitDNSRoutes": {"APP.EXAMPLE.": [{"Addr": url} for url in urls],
      "jetersen.dev": [{"Addr": urls[0]}]}}
    self.assertEqual(work.dns_plan(["app.example"], dns),
      ("server=/app.example/127.0.0.1#5354\n", {"app.example": urls}))

  def test_peer_dns_rejects_non_tailnet_endpoints_and_url_injection(self):
    for url in ["https://100.64.165.232:63028/dns-query", "http://1.1.1.1:53/dns-query",
        "http://localhost:53/dns-query", "http://100.64.165.232/dns-query",
        "http://100.64.165.232:0/dns-query", "http://100.64.165.232:65536/dns-query",
        "http://user@100.64.165.232:53/dns-query", "http://100.64.165.232:53/other",
        "http://100.64.165.232:53/dns-query?dns=x", "http://100.64.165.232:53/dns-query#x",
        "http://[fd00::1]:53/dns-query", "http://100.64.165.232:53/dns-query\n"]:
      with self.subTest(url=url), self.assertRaises(ValueError):
        work.peer_doh_url(url)

  def test_bridge_updates_endpoint_ports_and_clears_policy_when_off(self):
    with tempfile.TemporaryDirectory() as root, patch.object(work, "RUN", Path(root)), patch.object(work, "run"):
      controller = self.controller(root)
      dns = {"SplitDNSRoutes": {"app.example": [{"Addr": "http://100.64.165.232:63028/dns-query"}]}}
      controller.sync_dns(["app.example"], dns)
      config = Path(root) / "peer-dns.json"
      self.assertEqual(json.loads(config.read_text()), {"app.example": ["http://100.64.165.232:63028/dns-query"]})
      dns["SplitDNSRoutes"]["app.example"][0]["Addr"] = "http://100.64.165.232:63029/dns-query"
      controller.sync_dns(["app.example"], dns)
      self.assertEqual(json.loads(config.read_text()), {"app.example": ["http://100.64.165.232:63029/dns-query"]})
      controller.sync_dns([])
      self.assertEqual(json.loads(config.read_text()), {})
      self.assertEqual((Path(root) / "dnsmasq.servers").read_text(), "")

  def test_split_dns_updates_upstream_without_changing_suffixes(self):
    with tempfile.TemporaryDirectory() as root, patch.object(work, "RUN", Path(root)), patch.object(work, "run") as run:
      controller = self.controller(root)
      dns = {"SplitDNSRoutes": {"corp.example": [{"Addr": "100.65.1.1"}]}}
      controller.sync_dns(["corp.example"], dns)
      controller.sync_dns(["corp.example"], dns)
      self.assertEqual(run.call_count, 1)
      dns["SplitDNSRoutes"]["corp.example"][0]["Addr"] = "100.65.1.2"
      controller.sync_dns(["corp.example"], dns)
      self.assertEqual(run.call_count, 2)
      self.assertEqual((Path(root) / "dnsmasq.servers").read_text(), "server=/corp.example/100.65.1.2\n")

  def controller(self, root):
    with patch.object(work, "ROOT", Path(root)):
      return work.Controller("auto", ["MSP"], False)

  def test_choice_persists_but_presence_does_not_survive_restart(self):
    with tempfile.TemporaryDirectory() as root:
      controller = self.controller(root)
      controller.request({"command": "off"})
      controller.request({"command": "presence", "location": "work", "ttl": 120})
      restored = self.controller(root)
      self.assertEqual(restored.state["mode"], "off")
      self.assertEqual(restored.presence, {})
      for ttl in [0, 301]:
        with self.assertRaises(ValueError):
          controller.request({"command": "presence", "location": "work", "ttl": ttl})
      with self.assertRaises(ValueError):
        controller.request({"command": "exec", "argv": ["sh"]})

  def test_failed_location_or_status_clears_routes_dns_and_connection(self):
    with tempfile.TemporaryDirectory() as root:
      controller = self.controller(root)
      with patch.object(controller, "reconcile", side_effect=OSError("no signal")), \
          patch.object(controller, "sync_routes") as routes, \
          patch.object(controller, "sync_dns") as dns, patch.object(work, "tailscale") as ts:
        controller.tick()
        routes.assert_called_once_with(set())
        dns.assert_called_once_with([])
        ts.assert_called_once_with("down")
        self.assertFalse(controller.snapshot["connected"])

  def test_off_clears_before_disconnect_and_does_not_query_wifi(self):
    with tempfile.TemporaryDirectory() as root:
      controller = self.controller(root)
      controller.request({"command": "off"})
      calls = []
      with patch.object(work, "tailscale", side_effect=lambda *args:
          calls.append(args) or json.dumps({"BackendState": "Running"})), \
          patch.object(controller, "sync_routes", side_effect=lambda x: calls.append("routes")), \
          patch.object(controller, "sync_dns", side_effect=lambda x: calls.append("dns")), \
          patch.object(work, "active_ssids") as wifi:
        controller.reconcile()
        wifi.assert_not_called()
        self.assertEqual(calls, [("status", "--json"), "routes", "dns", ("down",)])

  def test_resume_preserves_existing_preferences(self):
    with tempfile.TemporaryDirectory() as root:
      controller = self.controller(root)
      controller.request({"command": "on"})
      with patch.object(work, "tailscale", return_value=json.dumps({"BackendState": "Stopped"})) as ts, \
          patch.object(controller, "sync_routes"), patch.object(controller, "sync_dns"), \
          patch.object(work, "resume") as resume:
        controller.reconcile()
        resume.assert_called_once_with()
        self.assertFalse(any(call.args == ("up",) for call in ts.call_args_list))


if __name__ == "__main__":
  unittest.main()
