#!/usr/bin/env bash
set -euo pipefail
# Explicit prerequisite check. Install these tools using the platform package manager.
for tool in chezmoi sops age python3; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
