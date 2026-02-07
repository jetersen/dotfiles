#!/usr/bin/env bash

# Check if Proton Pass cli ie. "pass-cli" is installed
if ! command -v pass-cli &> /dev/null; then
  echo "installing pass-cli"
  # check if brew is installed
  if ! command -v brew &> /dev/null; then
    echo "Homebrew is not installed. Please install Homebrew first: https://brew.sh"
    exit 1
  fi
  brew install protonpass/tap/pass-cli --quiet
fi
