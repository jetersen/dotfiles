// Run against the built Framework IdleService.qml, not a copied fixture.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(process.argv[2], 'utf8');
const body = source.match(/function _applyMonitorEnableds\(\) \{([\s\S]*?)\n    \}/)?.[1];
assert.ok(body, 'DMS idle monitor setup must remain identifiable');
const apply = new Function('state', `with (state) { ${body} }`);
for (const externalInhibitActive of [false, true]) {
  for (const idleInhibited of [false, true]) {
    for (const enabled of [false, true]) {
      const state = {
        enabled, externalInhibitActive, SessionService: { idleInhibited },
        monitorTimeout: 900, lockTimeout: 900, suspendTimeout: 900,
        postLockMonitorActive: false,
        monitorOffMonitor: {}, postLockMonitorOffMonitor: {},
        lockMonitor: {}, suspendMonitor: {},
      };
      apply(state);
      assert.equal(state.monitorOffMonitor.enabled, enabled && !idleInhibited);
      assert.equal(state.lockMonitor.enabled, enabled && !idleInhibited && !externalInhibitActive);
      assert.equal(state.suspendMonitor.enabled, state.lockMonitor.enabled);
      state.postLockMonitorActive = true;
      apply(state);
      assert.equal(state.monitorOffMonitor.enabled, false);
      assert.equal(state.postLockMonitorOffMonitor.enabled, enabled);
    }
  }
}
for (const monitor of ['monitorOffMonitor', 'postLockMonitorOffMonitor']) {
  const block = source.split(`id: ${monitor}\n`)[1]?.split('onIsIdleChanged:')[0];
  assert.match(block, /respectInhibitors: false/);
}
for (const monitor of ['lockMonitor', 'suspendMonitor']) {
  const block = source.split(`id: ${monitor}\n`)[1]?.split('onIsIdleChanged:')[0];
  assert.match(block, /respectInhibitors: root.respectInhibitors/);
}
console.log('Framework display timers ignore application inhibitors; lock, suspend and Keep Awake gates passed.');
