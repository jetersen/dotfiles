#!/usr/bin/env bash
# Keep application volume independent of system volume. Leave identity, secrets,
# software volume, mute, and all other app-owned settings unchanged.
set -euo pipefail

jq --slurp '
  (if length == 0 then
    # Required fields without serde defaults in desktop-app 0.7.1.
    {discord_rpc_enabled: true, start_minimized: false, autostart: false}
  elif length == 1 and (.[0] | type) == "object" then .[0]
  else error("expected one settings object") end)
  | .volume_control_mode = "software"
'
