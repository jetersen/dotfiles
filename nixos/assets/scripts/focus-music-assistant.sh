#!/usr/bin/env bash
set -euo pipefail

focus_window() {
  local window_id
  window_id=$(niri msg -j windows 2>/dev/null | jq -r \
    'first(.[] | select(.app_id == "music-assistant-companion") | .id) // empty') || return 1
  [[ -n "$window_id" ]] || return 1
  niri msg action focus-window --id "$window_id" >/dev/null 2>&1
}

if focus_window; then
  exit 0
fi

# A window hidden to the tray is absent from Niri's window list. MPRIS Raise
# asks the existing companion to show, unminimize and focus its main window.
while read -r name _; do
  case "$name" in
    org.mpris.MediaPlayer2.io_music_assistant_companion.instance*)
      if busctl --user call "$name" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2 Raise >/dev/null 2>&1; then
        for ((attempt = 0; attempt < 20; attempt++)); do
          if focus_window; then exit 0; fi
          sleep 0.05
        done
        exit 0
      fi
      ;;
  esac
done < <(busctl --user --no-pager --no-legend list 2>/dev/null || true)

exec music-assistant-companion "$@"
