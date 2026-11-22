$custom[0] as $custom
| if ($custom | type) != "object" then error("Custom shortcodes must be an object") else . end
| reduce .[] as $entry ({};
    reduce $entry.aliases[] as $alias (.;
      if has($alias) and .[$alias] != $entry.emoji then
        error("Conflicting emoji shortcode: " + $alias)
      else .[$alias] = $entry.emoji end))
| reduce ($custom | to_entries[]) as $entry (.;
    if ($entry.key | test("^[a-z0-9_+\\-]+$") | not) then
      error("Use a lowercase shortcode without colons: " + $entry.key)
    elif ($entry.value | type) != "string" or ($entry.value | test("\\S") | not) then
      error("Empty or invalid replacement for " + $entry.key)
    else .[$entry.key] = $entry.value end)
| . as $aliases
| reduce to_entries[] as $entry ({};
    ($entry.value | gsub("\uFE0F"; "")) as $key
    | .[$key] += [$entry.key])
| . as $byEmoji
| {
    byEmoji: $byEmoji,
    customEntries: (
      reduce $custom[] as $emoji ([];
        if any(.[]; .emoji == $emoji) then . else
          ($byEmoji[$emoji | gsub("\uFE0F"; "")]) as $names
          | . + [{emoji: $emoji, name: $names[0], keywords: $names, category: "custom"}]
        end)
    ),
    shortcodes: $aliases,
    matches: ($aliases | to_entries | sort_by(.key)
      | map({trigger: (":" + .key + ":"), replace: .value}))
  }
