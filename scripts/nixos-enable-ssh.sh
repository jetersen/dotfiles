#!/usr/bin/env bash
# Run from the Zalman's HDD in the standard NixOS live environment.
set -euo pipefail

if (( EUID != 0 )); then
  exec sudo bash "$0" "$@"
fi

if [[ ! -e /etc/NIXOS || ! -e /iso ]]; then
  echo 'Run this only in the NixOS live installer.' >&2
  exit 1
fi

key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII/bjg+lLtcCJAOpG2ZRE4BzIHx4EpqR8OvhXZ3tmguY me@jetersen.dev'
install -d -m 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
if ! grep -qxF "$key" /root/.ssh/authorized_keys; then
  printf '\n%s\n' "$key" >> /root/.ssh/authorized_keys
fi
systemctl start sshd

echo 'SSH is ready. Ethernet addresses:'
ip -br -4 address
echo 'SSH host-key fingerprint:'
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
