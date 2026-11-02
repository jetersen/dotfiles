# Called as the desktop user, with its XDG_RUNTIME_DIR set by the host wrapper.
operation=${1:?missing operation}
case "$operation" in
  read) [[ $# == 1 ]] ;;
  set|limit|limit-unmute)
    [[ $# == 2 && "$2" =~ ^[0-9]+([.][0-9]+)?$ ]]
    awk -v value="$2" 'BEGIN { exit !(value >= 0 && value <= 100) }'
    ;;
  *) exit 2 ;;
esac

# Pin all steps to one output, including lowering volume before unmuting.
sink=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | awk 'NR == 1 && $1 == "id" { gsub(/,/, "", $2); print $2 }')
[[ "$sink" =~ ^[0-9]+$ ]]
case "$operation" in
  set) wpctl set-volume "$sink" "$2%" ;;
  limit|limit-unmute)
    fraction=$(awk -v value="$2" 'BEGIN { printf "%.6f", value / 100 }')
    # A relative zero change with --limit clamps without raising quieter output.
    wpctl set-volume --limit "$fraction" "$sink" 0%+
    if [[ "$operation" == limit-unmute ]]; then wpctl set-mute "$sink" 0; fi
    ;;
esac
current=$(wpctl inspect @DEFAULT_AUDIO_SINK@ | awk 'NR == 1 && $1 == "id" { gsub(/,/, "", $2); print $2 }')
[[ "$current" == "$sink" ]]
wpctl get-volume "$sink"
