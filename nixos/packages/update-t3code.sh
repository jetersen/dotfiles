#!/usr/bin/env bash
set -euo pipefail
version=${1:?Usage: update-t3code.sh VERSION}
version=${version#v}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
release=$(curl -fsSL "https://api.github.com/repos/pingdotgg/t3code/releases/tags/v$version")
cli=$(jq -er --arg name "t3-$version-linux-x64.tar.gz" '.assets[] | select(.name == $name) | .digest' <<< "$release")
desktop=$(jq -er --arg name "T3-Code-$version-x86_64.AppImage" '.assets[] | select(.name == $name) | .digest' <<< "$release")
[[ $cli =~ ^sha256:[a-f0-9]{64}$ && $desktop =~ ^sha256:[a-f0-9]{64}$ ]]
temporary=$(mktemp "$directory/.t3-manifest.XXXXXX")
trap 'rm -f "$temporary"' EXIT
jq --arg version "v$version" --arg cli "${cli#sha256:}" --arg desktop "${desktop#sha256:}" \
  '.t3code = {repo: "pingdotgg/t3code", version: $version, cliSha256: $cli, desktopSha256: $desktop}' \
  "$directory/workstation-manifest.json" > "$temporary"
chmod 644 "$temporary"
mv "$temporary" "$directory/workstation-manifest.json"
printf 'Pinned T3 Code %s. Review both artifact hashes and rebuild NixOS.\n' "$version"
