#!/usr/bin/env bash

# Check if Proton Pass cli ie. "pass-cli" is installed
if ! command -v pass-cli &> /dev/null; then
  echo "installing pass-cli"
  if [ -f /etc/arch-release ]; then
    paru -Sq --noconfirm --needed proton-pass-cli-bin
  else
    # add more distros here as needed
    echo "unsupported linux distribution"
    exit 1
  fi
fi
