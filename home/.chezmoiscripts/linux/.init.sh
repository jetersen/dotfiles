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

# Check login status of Proton Pass CLI, if not logged in, prompt the user to log in
if ! pass-cli test &> /dev/null; then
  echo "Please log in to Proton Pass CLI..."
  if ! login_output=$(pass-cli login 2>&1); then
    if [[ $login_output != *"Already authenticated"* ]]; then
      echo "$login_output" >&2
      exit 1
    fi
  fi
fi
