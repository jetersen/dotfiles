"""Read-only Wayland check for Storage Monitor updates behind a stable symlink.

Usage: python3 tests/check_storage_monitor_reload.py OLD_PLUGIN NEW_PLUGIN DUX_ROOT [--actions-available]
Use a legacy plugin without the guarded popout as OLD_PLUGIN. This exercises the
real Qt cache in one process; it creates no windows and invokes no disk actions.
The Framework root must be present. --actions-available expects Gio support but
does not invoke any disk actions.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('old', type=Path)
parser.add_argument('new', type=Path)
parser.add_argument('dux', type=Path)
parser.add_argument('--actions-available', action='store_true')
args = parser.parse_args()
old, new, dux = (p.resolve() for p in (args.old, args.new, args.dux))
with tempfile.TemporaryDirectory(prefix='storage-reload-regression-') as tmp:
    root = Path(tmp)
    for p in dux.iterdir():
        if p.is_dir():
            (root / p.name).symlink_to(p)
    link = root / 'plugin'
    link.symlink_to(old)
    result = root / 'result'
    qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import "./plugin" as Seed
ShellRoot {
    id: root
    property var widget: null
    property var popout: null
    property int phase: 0
    property string result: ""
    property int code: 0
    function load(revision) {
        const c = Qt.createComponent(PLUGIN_URL + "/" + (revision === 1 ? "StorageMonitorWidget.qml" : NEW_COMPONENT) + "?revision=" + revision);
        if (c.status !== Component.Ready) throw new Error(c.errorString());
        widget = c.createObject(root);
        if (!widget) throw new Error("widget failed");
        popout = widget.popoutContent.createObject(root, {visible: false});
        if (!popout) throw new Error("popout failed");
    }
    Process {
        id: swap
        command: ["ln", "-sfn", NEW_SOURCE, LINK_PATH]
        onExited: {
            try { root.load(2); root.phase = 2; }
            catch (e) { root.result = "FAIL: " + e; root.code = 1; report.running = true; }
        }
    }
    Process {
        id: report
        command: ["sh", "-c", 'printf "%s" "$1" > "$2"', "report", root.result, RESULT_PATH]
        onExited: Qt.exit(root.code)
    }
    Component.onCompleted: {
        try { load(1); phase = 1; }
        catch (e) { result = "FAIL: " + e; code = 1; report.running = true; }
    }
    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: {
            if (root.phase === 1) {
                root.popout.destroy(); root.widget.destroy();
                root.phase = 0; swap.running = true;
            } else if (root.phase === 2) {
                if (root.widget.storage.probing) return;
                if (!root.popout || !root.widget) throw new Error("missing instance");
                const same = root.popout.storage === root.widget.storage;
                const modern = root.popout.pendingVerb !== undefined;
                const parts = root.popout.storage.partitions;
                const roots = parts.filter(p => p.name === "system-root");
                const safe = roots.length === 1 && roots[0].mounted && !roots[0].manageable;
                const ok = same && modern && safe && root.popout.storage.actionsAvailable === EXPECT_ACTIONS;
                root.result = JSON.stringify({ok: ok, sameSingleton: same, modernPopout: modern, safeRoot: safe, partitions: parts.map(p => ({name:p.name, mounted:p.mounted, manageable:p.manageable}))});
                root.code = ok ? 0 : 1;
                root.phase = 3; report.running = true;
            }
        }
    }
}
'''
    for key, value in {'EXPECT_ACTIONS': args.actions_available, 'PLUGIN_URL': link.as_uri(), 'NEW_SOURCE': str(new), 'LINK_PATH': str(link), 'RESULT_PATH': str(result), 'NEW_COMPONENT': json.loads((new / 'plugin.json').read_text())['component'].removeprefix('./')}.items():
        qml = qml.replace(key, json.dumps(value))
    shell = root / 'shell.qml'
    shell.write_text(qml)
    try:
        proc = subprocess.run(['quickshell', '--path', str(shell), '--no-color'], env=dict(os.environ, QT_QPA_PLATFORM='wayland'), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=35)
    except subprocess.TimeoutExpired as error:
        print((error.stdout or b'').decode(errors='replace')[-6000:])
        raise SystemExit('QML reload check timed out')
    print(result.read_text() if result.exists() else proc.stdout[-6000:])
    if proc.returncode:
        print('QML log lines:', len(proc.stdout.splitlines()))
    sys.exit(proc.returncode)
