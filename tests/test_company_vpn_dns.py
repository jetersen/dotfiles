"""Exercise the packaged reconciler without a desktop, VPN, or system D-Bus."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PLUGIN, NODE = sys.argv[1:3]
HELPER = Path(PLUGIN) / "helper"
del sys.argv[1:3]
spec = importlib.util.spec_from_file_location('split_dns', Path(HELPER) / 'split_dns.py')
dns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dns)


class ReconcilerTests(unittest.TestCase):
  def test_packaged_widget_uses_a_store_specific_component_url(self):
    plugin = Path(PLUGIN)
    manifest = json.loads((plugin / 'plugin.json').read_text())
    store_hash = plugin.name.split('-', 1)[0]
    self.assertEqual(manifest['component'], './OpenVpn3Widget-' + store_hash + '.qml')
    widget = plugin / manifest['component']
    self.assertEqual(widget.read_text(), (plugin / 'OpenVpn3Widget.qml').read_text())
    self.assertIn('import "file:' + str(plugin) + '"', widget.read_text())

  def test_packaged_widget_recovers_service_failure_and_retries_dns(self):
    # Execute the packaged QML's refresh and snapshot callbacks with a failed
    # initial D-Bus snapshot, then a successful fallback refresh and overwrite.
    result = subprocess.run([NODE, '-e', r"""
      const fs = require('fs'), vm = require('vm'), assert = require('assert');
      const plugin = process.argv[1];
      assert(!JSON.parse(fs.readFileSync(plugin + '/plugin.json')).startupCheck,
             'packaged dependencies must not be gated on transient D-Bus readiness');
      const qml = fs.readFileSync(plugin + '/OpenVpn3Service.qml', 'utf8');
      function bodyAfter(marker, offset = 0) {
        const start = qml.indexOf('{', qml.indexOf(marker, offset));
        assert(start >= 0);
        let depth = 1, end = start + 1;
        while (depth) {
          const c = qml[end++];
          if (c === '{') depth++;
          if (c === '}') depth--;
        }
        return qml.slice(start + 1, end - 1);
      }
      const root = {dnsRefreshPending:false, refreshInFlight:false,
                    reconcileSessionSubscriptions(){}, syncDns(){syncs++},
                    parseResponse:JSON.parse, responseError:()=> 'not ready'};
      let syncs = 0;
      const context = vm.createContext({root, Qt:{callLater:f=>f()},
        snapshotTimeout:{restart(){}}, snapshotProcess:{running:false}});
      // QML unqualified property references refer to its root singleton.
      Object.defineProperties(context, Object.fromEntries(
        ['dnsRefreshPending','refreshInFlight','refreshPending'].map(key=>
          [key,{get:()=>root[key],set:value=>root[key]=value}])));
      const signature = qml.match(/function refresh\(([^)]*)\)/)[1];
      root.refresh = vm.runInContext('(function(' + signature + '){' +
                                     bodyAfter('function refresh(') + '})', context);
      const snapshotOffset = qml.indexOf('id: snapshotProcess');
      const callback = '{' + bodyAfter('onStreamFinished:', snapshotOffset) + '}';
      root.refresh();
      context.text = JSON.stringify({ok:false});
      vm.runInContext(callback, context);
      assert.equal(syncs, 0);
      root.refreshInFlight = false;
      // The existing periodic callback is used, without an additional timer.
      const periodic = qml.match(/onTriggered: root.refresh\([^)]*\)/)[0].split(': ')[1];
      vm.runInContext(periodic, context);
      context.text = JSON.stringify({ok:true,data:{profiles:[],sessions:[]}});
      vm.runInContext(callback, context);
      assert.equal(syncs, 1);
      root.refreshInFlight = false;
      vm.runInContext(periodic, context);
      vm.runInContext(callback, context);
      assert.equal(syncs, 2);
    """, PLUGIN], capture_output=True, text=True)
    self.assertEqual(result.returncode, 0, result.stderr)

  def test_cli_session_retries_missing_dns_and_repairs_overwritten_routes(self):
    class Resolver:
      current = {'index': 9, 'domains': [['.', True]], 'default': True, 'has_dns': False}
      writes = []

      def read(self, device):
        self_outer.assertEqual(device, 'tun0')
        return copy.deepcopy(self.current)

      def write(self, device, domains, default):
        self_outer.assertEqual(device, 'tun0')
        self.writes.append((domains, default))
        self.current.update(domains=domains, default=default)

    self_outer = self
    resolver = Resolver()
    with tempfile.TemporaryDirectory() as directory:
      provider = Path(directory) / 'domains.json'
      provider.write_text(json.dumps(['work.example']))
      profiles = {'work': {'enabled': True, 'file': str(provider)}}
      sessions = [{'path': '/session/cli', 'active': True, 'device_name': 'tun0', 'config_name': 'work'}]
      state = Path(directory) / 'state.json'
      self.assertEqual(dns.sync(profiles, sessions, resolver, state)['work']['state'], 'waiting')
      resolver.current['has_dns'] = True
      self.assertEqual(dns.sync(profiles, sessions, resolver, state)['work']['state'], 'applied')
      desired = ([['work.example', True]], False)
      self.assertEqual(resolver.writes, [desired])
      dns.sync(profiles, sessions, resolver, state)
      self.assertEqual(resolver.writes, [desired])
      resolver.current.update(domains=[['.', True]], default=True)
      dns.sync(profiles, sessions, resolver, state)
      self.assertEqual(resolver.writes, [desired, desired])
      # Invalid provider data must retain the last working routing configuration.
      provider.write_text('["."]')
      self.assertEqual(dns.sync(profiles, sessions, resolver, state)['work']['state'], 'error')
      self.assertEqual(resolver.writes, [desired, desired])


if __name__ == '__main__':
  unittest.main()
