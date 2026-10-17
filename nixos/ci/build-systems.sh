#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must name the job temporary directory}"
roots=${CI_GCROOTS:-/nix/var/nix/gcroots}

# One evaluator and build budget share work between the two host configurations.
# Keep both results rooted before parsing or updating the named deployment roots.
time nix build .#nixosConfigurations.framework.config.system.build.toplevel \
  .#nixosConfigurations.rocket.config.system.build.toplevel \
  --no-update-lock-file --out-link "$roots/ci-systems" --json \
  > "$RUNNER_TEMP/systems.json"

for host in framework rocket; do
  jq -er --arg host "$host" '
    [.[].outputs.out | select(test("/[^/]+-nixos-system-" + $host + "-"))]
    | if length == 1 then .[0] else error("Expected one system output for " + $host) end
  ' "$RUNNER_TEMP/systems.json" > "$RUNNER_TEMP/$host-system"
done

for host in framework rocket; do
  nix-store --realise "$(cat "$RUNNER_TEMP/$host-system")" \
    --add-root "$roots/ci-$host"
done

time nix eval --raw .#localGitSyncSource --no-update-lock-file \
  > "$RUNNER_TEMP/local-git-sync-source"
nix-store --realise "$(cat "$RUNNER_TEMP/local-git-sync-source")" \
  --add-root "$roots/ci-local-git-sync-source"
