"""Instantiate the widget, both bar pills and popup against the installed Dux QML."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

dux = Path(sys.argv[1]).resolve()
plugin = Path(__file__).resolve().parents[1] / "nixos/home/work-tailnet/WorkTailnet.qml"
with tempfile.TemporaryDirectory(prefix="work-tailnet-ui-") as tmp:
  root = Path(tmp)
  for path in dux.iterdir():
    if path.is_dir():
      (root / path.name).symlink_to(path)
  helper = root / "status"
  helper.write_text("#!/bin/sh\nprintf '%s\\n' '{\"mode\":\"auto\",\"connected\":false,\"backend\":\"NeedsLogin\"}'\n")
  helper.chmod(0o755)
  (root / "WorkTailnet.qml").write_text(plugin.read_text().replace("@work-tailnet@", str(helper)).replace("@terminal@", "/bin/false").replace("@auto-available@", "true" if "--auto" in sys.argv[2:] else "false"))
  (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property var widget: WorkTailnet {}
    property var popout: widget.popoutContent.createObject(root)
    property var horizontal: widget.horizontalBarPill.createObject(root)
    property var vertical: widget.verticalBarPill.createObject(root)
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            let ok = root.widget.connectionState.mode === "auto" && root.popout && root.horizontal && root.vertical;
            ok = ok && root.widget.popupTitle === "Work tailnet";
            root.widget.connectionState = {mode: "on", connected: true, tailnetName: "example.work"};
            ok = ok && root.widget.popupTitle === "example.work";
            for (const entry of [
                [{mode: "on", connected: true, backend: "Running"}, "work"],
                [{mode: "off", connected: false, backend: "Stopped"}, "work_off"],
                [{mode: "auto", connected: true, backend: "Running"}, "work"],
                [{mode: "auto", connected: false, backend: "Stopped"}, "work_off"],
                [{mode: "on", connected: false, backend: "Starting"}, "work_off"],
                [{mode: "on", connected: false, backend: "NeedsLogin", hasProfile: false}, "work_off"]
            ]) {
                root.widget.connectionState = entry[0];
                ok = ok && root.horizontal.name === entry[1] && root.vertical.name === entry[1];
                ok = ok && root.horizontal.filled === entry[0].connected;
            }
            root.widget.connectionState = {mode: "off", connected: false, hasProfile: true, tailnetName: "example.work"};
            ok = ok && !root.widget.showSignIn;
            root.widget.connectionState = {mode: "off", connected: false, hasProfile: false};
            ok = ok && root.widget.showSignIn;
            ok = ok && root.widget.modeChoices.includes("auto") === root.widget.autoAvailable;
            root.widget.error = "Service unavailable";
            ok = ok && root.horizontal.name === "error" && root.vertical.name === "error";
            console.log(ok ? "PASS work tailnet widget" : "FAIL work tailnet widget");
            Qt.exit(ok ? 0 : 1);
        }
    }
}''')
  result = subprocess.run(["quickshell", "--path", str(root / "shell.qml"), "--no-color"],
    env=dict(os.environ, QT_QPA_PLATFORM="wayland", HOME=str(root),
      XDG_CONFIG_HOME=str(root / "config"), XDG_DATA_HOME=str(root / "data"),
      XDG_CACHE_HOME=str(root / "cache")), text=True,
    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=25)
  print(result.stdout[-6000:])
  sys.exit(result.returncode)
