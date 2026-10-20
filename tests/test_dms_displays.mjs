// Pass the installed DisplayConfigState.qml and the evaluated managed profiles.
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

const source = readFileSync(process.argv[2], 'utf8');
const profilesPath = process.argv[3];
const profiles = JSON.parse(readFileSync(profilesPath, 'utf8'));
function upstreamFunction(name, ...parameters) {
  const body = source.match(new RegExp(`    function ${name}\\([^)]*\\) \\{([\\s\\S]*?)\\n    \\}`))?.[1];
  assert.ok(body, `DMS ${name} must remain identifiable`);
  return new Function(...parameters, body);
}
const getOutputIdentifier = upstreamFunction('getOutputIdentifier', 'output', 'outputName', 'SettingsData', 'CompositorService');
const findConfigBody = upstreamFunction('findConfigEntryByFingerprint', 'data', 'outputIdentifiers', 'autoOnly', 'outputSetFingerprint', 'configFingerprint');
const fingerprint = upstreamFunction('outputSetFingerprint', 'outputIdentifiers');
const configFingerprint = upstreamFunction('configFingerprint', 'configEntry');
const findConfig = (...args) => findConfigBody(...args, fingerprint, configFingerprint);
const panel = { make: 'China Star Optoelectronics Technology Co., Ltd', model: 'MND508ZB1-1', serial: null };
const monitor = serial => ({ make: 'Dell Inc.', model: 'DELL P2725D', serial });
const identifier = (output, connector) => getOutputIdentifier(output, connector, { displayNameMode: 'model' }, { isNiri: true });
const panelId = identifier(panel, 'eDP-1');
const data = { configurations: profiles };
for (const connectors of [['DP-7', 'DP-9'], ['DP-8', 'DP-11']]) {
  const ids = [panelId, ...['24CRZ64', '3S5S864'].map((serial, i) => identifier(monitor(serial), connectors[i]))];
  const match = findConfig(data, ids, false);
  assert.equal(match.entry.id, 'framework-work-dock');
  assert.equal(match.entry.outputs[panelId].disabled, true);
  assert.equal(Object.values(match.entry.outputs).filter(o => !o.disabled).length, 2);
}
const laptop = findConfig(data, [panelId], false).entry.outputs[panelId];
assert.equal(laptop.disabled, false);
assert.equal(laptop.scale, 1.5);
assert.equal(findConfig(data, [panelId, identifier(monitor('different'), 'DP-7')], false), null);

const directory = mkdtempSync(join(tmpdir(), 'dms-displays-'));
try {
  const config = join(directory, 'DankMaterialShell');
  const run = () => execFileSync(process.argv[4], [profilesPath], {
    env: { ...process.env, XDG_CONFIG_HOME: directory, PATH: '/no-ambient-tools' },
  });
  const read = name => readFileSync(join(config, name), 'utf8');
  run();
  assert.deepEqual(JSON.parse(read('monitors.json')), { version: 1, configurations: profiles });
  assert.deepEqual(JSON.parse(read('settings.json')), { displayNameMode: 'model', displayProfileAutoSelect: true });
  const local = { id: 'local-layout', name: 'Other desk', outputs: { 'HDMI-A-1': { scale: 2 } } };
  const old = { ...profiles[0], name: 'Outdated managed profile' };
  writeFileSync(join(config, 'monitors.json'), JSON.stringify({ version: 1, extra: 'keep', configurations: [local, old] }));
  writeFileSync(join(config, 'settings.json'), JSON.stringify({ wallpaperPath: '/local/wallpaper', displayNameMode: 'system' }));
  run();
  assert.deepEqual(JSON.parse(read('monitors.json')), { version: 1, extra: 'keep', configurations: [...profiles, local] });
  assert.equal(JSON.parse(read('settings.json')).wallpaperPath, '/local/wallpaper');
  const before = ['monitors.json', 'settings.json'].map(read);
  run();
  assert.deepEqual(['monitors.json', 'settings.json'].map(read), before);
} finally {
  rmSync(directory, { recursive: true, force: true });
}
console.log('DMS profiles match either USB-C port and restore the laptop; fresh setup, local settings and idempotence passed.');
