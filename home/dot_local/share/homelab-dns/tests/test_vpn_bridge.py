"""Reject stale interfaces and unsafe routing intent at the root boundary."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import vpn_bridge


class Bridge(unittest.TestCase):
    def test_interface_identity(self):
        intent = {'tun1': {'index': 7, 'domains': [['corp.test', True]]}}
        self.assertEqual(vpn_bridge.routes(intent, {}, lambda _: 7), [])
        self.assertEqual(vpn_bridge.routes(intent, {'tun1': ['100.96.0.1']}, lambda _: 8), [])
        def missing(_):
            raise OSError('Interface disappeared')
        self.assertEqual(vpn_bridge.routes(intent, {'tun1': ['100.96.0.1']}, missing), [])
        result = vpn_bridge.routes(intent, {'tun1': ['100.96.0.1']}, lambda _: 7)
        self.assertEqual(result[0]['domains'], ['corp.test'])
        self.assertEqual(result[0]['servers'], ['100.96.0.1'])

    def test_intent_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'intent.json'
            original_open = os.open
            def open_intent(_, flags):
                return original_open(path, flags)
            with patch.object(vpn_bridge.os, 'open', side_effect=open_intent):
                for domain, route in [('.', True), ('corp.test', False), ('corp.test";bad()', True)]:
                    path.write_text(json.dumps({'tun1': {'index': 7, 'domains': [[domain, route]]}}))
                    with self.assertRaises(AssertionError):
                        vpn_bridge.read_intent(os.getuid())
                path.write_text(json.dumps({'tun1': {'index': 7, 'domains': [['corp.test', True]]}}))
                self.assertIn('tun1', vpn_bridge.read_intent(os.getuid()))
                with self.assertRaises(AssertionError):
                    vpn_bridge.read_intent(os.getuid() + 1)
                path.unlink()
                path.symlink_to(Path(directory) / 'missing')
                with self.assertRaises(OSError):
                    vpn_bridge.read_intent(os.getuid())


if __name__ == '__main__':
    unittest.main()
