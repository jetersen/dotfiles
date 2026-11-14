// Exercise the packaged QML search against its real emoji catalog.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const directory = process.argv[2];
const source = readFileSync(`${directory}/EmojiPicker.qml`, 'utf8');
const rankBody = source.match(/function searchRank\(entry, query\) \{([\s\S]*?)\n    \}/)?.[1];
const searchBody = source.match(/readonly property var visibleEntries: \{([\s\S]*?)\n    \}/)?.[1];
assert.ok(rankBody && searchBody, 'production search must be identifiable');
const catalog = vm.createContext({});
vm.runInContext(readFileSync(`${directory}/emoji-data.js`, 'utf8'), catalog);
const shortcodes = vm.createContext({});
vm.runInContext(readFileSync(`${directory}/EmojiShortcodes.js`, 'utf8'), shortcodes);
const root = {
  allEntries: [],
  recentLimit: 30,
  selectedCategory: 'recent',
  effectiveEmoji: entry => entry.emoji,
  stripSkinTone: emoji => emoji.replace(/[\u{1F3FB}-\u{1F3FF}]/gu, ''),
  findEntry: emoji => root.allEntries.find(entry => entry.emoji === emoji),
};
const loadBody = source.match(/function loadData\(\) \{([\s\S]*?)\n    \}/)?.[1];
assert.ok(loadBody, 'production catalog loader must be identifiable');
new Function('root', 'EmojiData', 'Shortcodes', 'PluginService', loadBody)(
  root, { getEntries: () => Array.from(catalog.getEntries()) }, shortcodes,
  { loadPluginState: () => ['😀'] });
root.searchRank = new Function('root', 'entry', 'query', rankBody).bind(null, root);
const search = new Function('root', searchBody).bind(null, root);
for (const [query, expected] of [
  ['rocket', '🚀'], [' ROCKET ', '🚀'], ['rocke', '🚀'], ['rock', '🪨'],
  ['grinning face', '😀'], ['woman astronaut', '👩‍🚀'], ['🚀', '🚀'],
  [':clap:', '👏'], [':clap', '👏'], ['clap:', '👏'],
  [':sweat_smile:', '😅'], [':tada:', '🎉'], [':+1:', '👍'], [':thumbsup:', '👍'],
  [':ship_it:', '🚢🚀'],
]) {
  root.query = query;
  const result = search();
  assert.equal(result[0]?.emoji.replace(/\uFE0F/g, ''), expected,
    `Enter should select ${expected} for ${query}`);
}
root.query = 'rocket';
assert.equal(search().length, 4, 'keyword matches remain available');
root.query = 'spacesuit';
assert.ok(search().some(entry => entry.emoji === '👩‍🚀'), 'keyword-only search still works');
root.query = 'no-such-emoji-xyz';
assert.equal(search().length, 0);
root.query = ':shipit:';
assert.equal(search().length, 0, 'Slack’s image shortcode must remain untouched');
assert.equal(root.findEntry('🚢🚀')?.name, 'ship_it', 'custom sequences support recents');
root.query = '';
assert.deepEqual(search().map(entry => entry.emoji), ['😀'], 'empty search preserves recents');
root.selectedCategory = 'travel-places';
assert.deepEqual(search(), root.entriesByCategory['travel-places'], 'empty search preserves category order');
root.query = ':rocket:';
assert.equal(search()[0]?.emoji, '🚀', 'shortcodes work in categories too');
root.selectedCategory = 'smileys-people';
assert.equal(search()[0]?.emoji, '🚀', 'shortcodes search across categories');
assert.match(source, /command: \["[^"\n]+", "pause"\]/);
assert.match(source, /if \(root.pickerRequested && exitCode === 0\) \{\s*pickerModal.open\(\)/);
assert.match(source, /onDialogClosed: \{[^}]*root.resumeExpansion\(\)/);
console.log('Emoji search: exact names, prefixes, keywords, direct emoji and empty queries passed.');
