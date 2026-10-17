#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?RUNNER_TEMP must name the job temporary directory}"
roots=${CI_GCROOTS:-/nix/var/nix/gcroots}

# Separate caches keep concurrent evaluators from contending on one SQLite file.
# A native build plan preserves Nix's evaluation cache on repeated revisions.
evaluate_system() {
  local host=$1 derivation
  export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}/eval-$host"
  time nix build ".#nixosConfigurations.$host.config.system.build.toplevel" \
    --no-update-lock-file --no-link --dry-run --json \
    > "$RUNNER_TEMP/$host-plan.json"
  derivation=$(jq -er '
    if length == 1 then .[0].drvPath else error("Expected one system derivation") end
  ' "$RUNNER_TEMP/$host-plan.json")
  if [[ "$derivation" != /nix/store/*-nixos-system-"$host"-*.drv ]]; then
    echo "Unexpected $host system derivation: $derivation" >&2
    return 1
  fi
  # Protect evaluated inputs until realization, including when the other host fails.
  ln -sfn "$derivation" "$roots/ci-eval-$host.drv"
  printf '%s\n' "$derivation" > "$RUNNER_TEMP/$host-derivation"
}

mkdir -p "$roots"
eval_pids=()
for host in framework rocket; do
  evaluate_system "$host" &
  eval_pids+=("$!")
done
eval_status=0
for pid in "${eval_pids[@]}"; do
  wait "$pid" || eval_status=1
done
if (( eval_status != 0 )); then
  exit "$eval_status"
fi

# Both plans must succeed before one build invocation realizes their shared graph.
# Keep the outputs rooted before updating the named deployment roots.
time nix build "$(cat "$RUNNER_TEMP/framework-derivation")^*" \
  "$(cat "$RUNNER_TEMP/rocket-derivation")^*" \
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
