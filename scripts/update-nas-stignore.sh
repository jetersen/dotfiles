#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_file="$script_dir/../home/git/dot_stignore"
target="/mnt/nvme/git/.stignore"
remote_tmp="/tmp/dot_stignore.$UID.$$"
expected_hash=$(sha256sum "$source_file" | awk '{print $1}')

cleanup() {
  ssh truenasadmin "rm -f -- '$remote_tmp'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

scp -q "$source_file" "truenasadmin:$remote_tmp"

ssh -t truenasadmin "
  set -e
  sudo install -o apps -g apps -m 0600 '$remote_tmp' '$target'
  printf '%s  %s\\n' '$expected_hash' '$target' | sudo sha256sum -c -
  rm -f -- '$remote_tmp'
  sudo stat -c 'mode=%a owner=%U:%G size=%s' '$target'
"
