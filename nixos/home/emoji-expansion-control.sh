# Keep the worker alive: restarting it opens Espanso's visible Wayland sync window.
# A marker also keeps layout-triggered worker reloads disabled while the picker is open.
runtime="${XDG_RUNTIME_DIR:?}/espanso-picker"
mkdir -p "$runtime"
exec 9>"$runtime/lock"
flock 9
case "${1:?pause or resume}" in
  pause)
    if [[ ! -f "$runtime/resume" ]] && systemctl --user is-active --quiet espanso.service; then
      touch "$runtime/resume"
      espanso cmd disable
    fi
    ;;
  resume)
    if [[ -f "$runtime/resume" ]]; then
      # Retain the marker if the command fails, allowing a later retry.
      if systemctl --user is-active --quiet espanso.service; then
        espanso cmd enable
      fi
      rm "$runtime/resume"
      # Usually no file changes are needed. A layout switch while paused may
      # have persisted enable=false for the new worker; clear that stale default.
      python3 - "$XDG_RUNTIME_DIR/espanso-niri/config/default.yml" <<'PYTHON'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
if path.exists():
    settings = json.loads(path.read_text())
    if settings.get("enable") is False:
        settings["enable"] = True
        temporary = path.with_suffix(".resume-tmp")
        temporary.write_text(json.dumps(settings) + "\n")
        temporary.replace(path)
PYTHON
    fi
    ;;
  *) exit 2 ;;
esac
