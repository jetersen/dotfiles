#!/usr/bin/env bash
set -euo pipefail

base_url=https://downloads.claude.ai/claude-code-releases
version="${1:-$(curl -fsSL "$base_url/latest")}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Invalid Claude Code version: %s\n' "$version" >&2
  exit 1
fi

directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
temporary=$(mktemp "$directory/.claude-manifest.XXXXXX")
trap 'rm -f "$temporary"' EXIT
curl -fsSL "$base_url/$version/manifest.json" -o "$temporary"
jq -e --arg version "$version" '
  .version == $version and
  (.platforms["linux-x64"].checksum | test("^[a-f0-9]{64}$"))
' "$temporary" >/dev/null
chmod 644 "$temporary"
mv "$temporary" "$directory/claude-code-manifest.json"
printf 'Pinned Claude Code %s. Review the diff and rebuild NixOS.\n' "$version"
