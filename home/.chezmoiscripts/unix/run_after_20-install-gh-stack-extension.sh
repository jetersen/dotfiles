#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required to install the gh-stack extension." >&2
  exit 1
fi

if ! gh extension list | grep -Fq "github/gh-stack"; then
  echo "Installing gh-stack GitHub CLI extension..."
  gh extension install github/gh-stack
fi
