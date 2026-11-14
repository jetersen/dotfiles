"""Generate picker aliases and Espanso matches from the same pinned catalog."""
import json
from pathlib import Path
import re
import sys


def generate(entries, custom, output):
    aliases = {}
    for entry in entries:
        emoji = entry['emoji']
        for alias in entry['aliases']:
            if alias in aliases and aliases[alias] != emoji:
                raise ValueError(f'Conflicting emoji shortcode: {alias}')
            aliases[alias] = emoji
    for alias, text in custom.items():
        if not re.fullmatch(r'[a-z0-9_+\-]+', alias):
            raise ValueError(f'Use a lowercase shortcode without colons: {alias!r}')
        if not isinstance(text, str) or not text.strip():
            raise ValueError(f'Empty or invalid replacement for {alias}')
    aliases.update(custom)
    by_emoji = {}
    for alias, text in aliases.items():
        by_emoji.setdefault(text.replace('\ufe0f', ''), []).append(alias)
    custom_entries = []
    for text in dict.fromkeys(custom.values()):
        names = by_emoji[text.replace('\ufe0f', '')]
        custom_entries.append({'emoji': text, 'name': names[0],
                               'keywords': names, 'category': 'custom'})
    (output / 'EmojiShortcodes.js').write_text(
        'var byEmoji = ' + json.dumps(by_emoji, ensure_ascii=False) + ';\n'
        + 'var customEntries = ' + json.dumps(custom_entries, ensure_ascii=False) + ';\n')
    (output / 'shortcodes.json').write_text(json.dumps(aliases, ensure_ascii=False) + '\n')
    matches = [{'trigger': f':{alias}:', 'replace': emoji}
               for alias, emoji in sorted(aliases.items())]
    # JSON is valid YAML; no extra YAML serializer is needed.
    (output / 'emoji.yml').write_text(json.dumps({'matches': matches}, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    generate(json.loads(Path(sys.argv[1]).read_text()),
             json.loads(Path(sys.argv[2]).read_text()), Path(sys.argv[3]))
