import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const source = readFileSync(process.argv[2], 'utf8');
const body = source.match(/    function panelShouldBeEnabled\([^)]*\) \{([\s\S]*?)\n    \}/)?.[1];
assert.ok(body);
const enabled = new Function('locked', 'greeter', 'outputs', body);
const panel = { make: 'China Star Optoelectronics Technology Co., Ltd', model: 'MND508ZB1-1', enabled: true };
const dell = serial => ({ make: 'Dell Inc.', model: 'DELL P2725D', serial, enabled: true });
for (const connectors of [['DP-7', 'DP-9'], ['DP-8', 'DP-11']]) {
  const dock = { 'eDP-1': panel, [connectors[0]]: dell('24CRZ64'), [connectors[1]]: dell('3S5S864') };
  assert.equal(enabled(false, false, dock), false, 'docked desktop disables the panel');
  assert.equal(enabled(true, false, dock), true, 'locking enables the panel');
  assert.equal(enabled(false, true, dock), true, 'greeter keeps the panel enabled');
  assert.equal(enabled(false, false, { ...dock, 'eDP-1': { ...panel, enabled: false } }), false, 'unlock restores the dock policy');
  delete dock[connectors[1]];
  assert.equal(enabled(false, false, dock), true, 'disconnecting a dock monitor restores the panel');
}
assert.equal(enabled(false, false, { 'eDP-1': panel }), true, 'laptop alone stays enabled');
assert.equal(enabled(true, false, {}), true, 'lock stays enabled during output discovery');
assert.equal(enabled(false, false, { 'eDP-1': panel, 'DP-1': dell('other') }), true, 'another desk is unaffected');
console.log('Framework panel lock/unlock, dock/undock and connector-independent policy passed.');
