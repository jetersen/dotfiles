#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must name the job temporary directory}"
roots=${CI_GCROOTS:-/nix/var/nix/gcroots}
mkdir -p "$roots"

# Discover all groups so a newly added flake check cannot silently miss CI.
names=$(nix eval --no-update-lock-file --json .#checks.x86_64-linux --apply builtins.attrNames)
mapfile -t checks < <(jq -er '.[] | ".#checks.x86_64-linux." + .' <<< "$names")
if (( ${#checks[@]} == 0 )); then
  echo 'No Nix checks were selected' >&2
  exit 1
fi
time nix build "${checks[@]}" --no-update-lock-file \
  --out-link "$roots/ci-checks" --json > "$RUNNER_TEMP/checks.json"
jq -er '.[].outputs[]' "$RUNNER_TEMP/checks.json" > "$RUNNER_TEMP/check-outputs"
