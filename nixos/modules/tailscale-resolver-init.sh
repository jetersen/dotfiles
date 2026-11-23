set -euo pipefail

resolver=${1:-/etc/resolv.conf}
fallback=${2:-/run/NetworkManager/no-stub-resolv.conf}

# Tailscale backs up this link and restores it on shutdown. Leave an existing
# resolver, including a dangling link, alone so startup never tramples DNS.
if [[ ! -e "$resolver" && ! -L "$resolver" ]]; then
  ln -s -- "$fallback" "$resolver"
fi
