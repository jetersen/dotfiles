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

# Check login status of Proton Pass CLI, if not logged in, prompt the user to log in
if ! pass-cli test &> /dev/null; then
  echo "Please log in to Proton Pass CLI..."
  pass-cli login
fi
