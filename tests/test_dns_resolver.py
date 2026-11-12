import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1] / "home/dot_local/share/homelab-dns/vpn_bridge.py"
spec = importlib.util.spec_from_file_location("vpn_bridge", SOURCE)
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)
BASE = "nameserver 127.0.0.2\nsearch personal.ts.net\noptions timeout:2 attempts:2\n"


class ResolverTests(unittest.TestCase):
  def test_connect_disconnect_and_domain_changes_preserve_personal_dns(self):
    with tempfile.TemporaryDirectory() as root:
      path = Path(root) / "search-domain.json"
      self.assertEqual(bridge.resolver_config(BASE, path), BASE)
      for domain in ("work.ts.net", "renamed.ts.net"):
        path.write_text(json.dumps(domain))
        result = bridge.resolver_config(BASE, path)
        self.assertEqual(result, BASE.replace("search personal.ts.net", "search personal.ts.net " + domain))
        self.assertEqual(bridge.resolver_config(result, path), result)
      path.write_text("null")
      self.assertEqual(bridge.resolver_config(BASE, path), BASE)

  def test_invalid_search_metadata_is_ignored(self):
    with tempfile.TemporaryDirectory() as root:
      path = Path(root) / "search-domain.json"
      for value in ([], {}, 12, "work.ts.net\nnameserver 1.2.3.4", "bad suffix", ""):
        path.write_text(json.dumps(value))
        self.assertEqual(bridge.resolver_config(BASE, path), BASE)
      path.write_text("invalid JSON")
      self.assertEqual(bridge.resolver_config(BASE, path), BASE)

  def test_resolver_is_world_readable_and_replacements_are_atomic(self):
    with tempfile.TemporaryDirectory() as root:
      path = Path(root) / "resolv.conf"
      for content in (BASE, BASE, BASE.replace("personal.ts.net", "personal.ts.net work.ts.net"), BASE):
        bridge.publish(path, content, mode=0o644)
        self.assertEqual(path.read_text(), content)
        self.assertEqual(path.stat().st_mode & 0o777, 0o644)
      self.assertFalse(path.with_suffix(".tmp").exists())
