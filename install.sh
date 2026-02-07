#!/usr/bin/env bash
set -euo pipefail

if ! command -v chezmoi &>/dev/null; then
  bin_dir="$HOME/.local/bin"
  chezmoi="$bin_dir/chezmoi"
  if command -v curl &>/dev/null; then
    sh -c "$(curl -fsLS get.chezmoi.io/lb)"
  elif command -v wget &>/dev/null; then
    sh -c "$(wget -qO- get.chezmoi.io/lb)"
  else
    echo "Error: curl or wget is required to install chezmoi." >&2
    exit 1
  fi
else
  chezmoi="$(command -v chezmoi)"
fi

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
exec "$chezmoi" init --apply "--source=$SCRIPT_DIR"
