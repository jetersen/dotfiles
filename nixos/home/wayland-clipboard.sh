#!/usr/bin/env bash
# Run wl-clipboard against the logged-in desktop, including over SSH or mosh.
set -euo pipefail

if [[ -z ${WAYLAND_DISPLAY:-} || -z ${XDG_RUNTIME_DIR:-} ]]; then
  # Tailscale SSH can omit the runtime directory that contains the user bus.
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  if [[ -z ${WAYLAND_DISPLAY:-} ]] &&
     display=$(timeout 5s systemctl --user show-environment --output=json |
       jq -er '.WAYLAND_DISPLAY | select(type == "string" and length > 0)'); then
    export WAYLAND_DISPLAY="$display"
  fi
fi

exec "$@"
