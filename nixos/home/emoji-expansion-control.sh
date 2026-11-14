# Pause the whole daemon so configuration reloads cannot re-enable it in the picker.
# Remember whether it was running; closing the picker must not start a stopped daemon.
runtime="${XDG_RUNTIME_DIR:?}/espanso-picker"
mkdir -p "$runtime"
exec 9>"$runtime/lock"
flock 9
case "${1:?pause or resume}" in
  pause)
    if systemctl --user is-active --quiet espanso.service; then
      touch "$runtime/resume"
      systemctl --user stop espanso.service
    fi
    ;;
  resume)
    if [[ -f "$runtime/resume" ]]; then
      # Retain the marker if starting fails, allowing a later retry.
      systemctl --user start espanso.service
      rm "$runtime/resume"
    fi
    ;;
  *) exit 2 ;;
esac
