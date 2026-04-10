#!/usr/bin/env bash
# Listens for Hyprland window open events and closes WoW Voice Proxy windows.
# These windows spawn from WoW's voice chat system and serve no useful purpose.

handle() {
    if [[ "$1" == openwindow* ]]; then
        data="${1#openwindow>>}"
        addr="${data%%,*}"
        title="$(echo "$data" | cut -d',' -f4-)"

        case "$title" in
            "World of Warcraft Voice Proxy"|"Fatal Error - WowVoiceProxy.exe")
                hyprctl dispatch closewindow "address:0x${addr}" >/dev/null 2>&1
                ;;
        esac
    fi
}

socat -U - "UNIX-CONNECT:/tmp/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock" \
    | while IFS= read -r line; do handle "$line"; done
