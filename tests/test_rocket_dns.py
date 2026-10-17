"""Verify Rocket's MagicDNS reconciler without changing live resolver settings."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch


SOURCE = Path(__file__).resolve().parents[1] / "home/dot_local/share/homelab-dns/reconcile.py"
SPEC = importlib.util.spec_from_file_location("rocket_reconcile", SOURCE)
reconcile = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reconcile)


class RocketDNS(unittest.TestCase):
    config = {"magic_suffix": "example.ts.net"}

    def test_explicit_suffix_does_not_query_tailscale(self):
        with patch.object(reconcile, "run") as run:
            self.assertEqual(reconcile.magic_suffix(self.config), "example.ts.net")
        run.assert_not_called()

    def test_runtime_suffix_supports_current_and_legacy_status(self):
        for status in (
            {"CurrentTailnet": {"MagicDNSSuffix": "example.ts.net"}},
            {"MagicDNSSuffix": "example.ts.net"},
        ):
            with self.subTest(status=status), patch.object(
                reconcile, "run", return_value=json.dumps(status)
            ) as run:
                self.assertEqual(reconcile.magic_suffix({}), "example.ts.net")
                run.assert_called_once_with("tailscale", "status", "--json")

    def test_invalid_suffix_is_rejected_before_resolver_changes(self):
        for suffix in (None, "", "example.com", "example.ts.net.", "~example.ts.net", 42):
            with self.subTest(suffix=suffix), patch.object(
                reconcile.Path, "exists", return_value=True
            ), patch.object(reconcile, "run", side_effect=["[]", json.dumps({"MagicDNSSuffix": suffix})]) as run:
                with self.assertRaises(ValueError):
                    reconcile.reconcile({})
                self.assertEqual(run.call_count, 2)
            with self.subTest(explicit=suffix), patch.object(reconcile, "run") as run:
                with self.assertRaises(ValueError):
                    reconcile.magic_suffix({"magic_suffix": suffix})
                run.assert_not_called()

    def test_runtime_status_can_recover_without_restarting(self):
        with patch.object(reconcile, "run", side_effect=[
            "{}", json.dumps({"CurrentTailnet": {"MagicDNSSuffix": "example.ts.net"}})
        ]):
            with self.assertRaises(ValueError):
                reconcile.magic_suffix({})
            self.assertEqual(reconcile.magic_suffix({}), "example.ts.net")

    def test_missing_tailscale_interface_does_not_change_resolver(self):
        with patch.object(reconcile.Path, "exists", return_value=False), patch.object(
            reconcile, "run", return_value="[]"
        ) as run:
            reconcile.reconcile(self.config)
        run.assert_called_once_with("resolvectl", "--json=short", "domain")

    def test_restores_magicdns_without_replacing_other_links(self):
        domains = [
            {"ifname": "eth0", "searchDomains": [{"name": "corp.test", "routeOnly": True}]},
            {"ifname": "tailscale0", "searchDomains": []},
        ]
        with patch.object(reconcile.Path, "exists", return_value=True), patch.object(
            reconcile, "run", side_effect=[json.dumps(domains), "[]", "", "", "tailscale0: yes", ""]
        ) as run:
            reconcile.reconcile(self.config)
        self.assertEqual(run.call_args_list[2].args, ("resolvectl", "dns", "tailscale0", "100.100.100.100"))
        self.assertEqual(run.call_args_list[3].args, ("resolvectl", "domain", "tailscale0", "example.ts.net"))
        self.assertEqual(run.call_args_list[5].args, ("resolvectl", "default-route", "tailscale0", "no"))

    def test_correct_settings_are_idempotent(self):
        domains = [{"ifname": "tailscale0", "searchDomains": [{"name": "example.ts.net", "routeOnly": False}]}]
        servers = [{"ifname": "tailscale0", "servers": [{"addressString": "100.100.100.100"}]}]
        with patch.object(reconcile.Path, "exists", return_value=True), patch.object(
            reconcile, "run", side_effect=[json.dumps(domains), json.dumps(servers), "tailscale0: no"]
        ) as run:
            reconcile.reconcile(self.config)
        self.assertEqual(run.call_count, 3)


if __name__ == "__main__":
    unittest.main()
