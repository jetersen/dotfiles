for supply in /sys/class/power_supply/*/online; do
  [[ -r "$supply" ]] || continue
  read -r online < "$supply" || continue
  [[ "$online" == 1 ]] && exit 0
done
for battery in /sys/class/power_supply/BAT*/capacity; do
  [[ -r "$battery" ]] || continue
  read -r capacity < "$battery" || continue
  if [[ "$capacity" =~ ^[0-9]{1,3}$ ]] && (( 10#$capacity <= 100 )); then
    if (( (10#$capacity <= 20) == low )); then
      printf '%s%%' "$capacity"
    fi
    exit 0
  fi
done
