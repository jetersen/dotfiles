import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Modules.Settings.DisplayConfig

Scope {
    id: root
    property string pluginId: ""
    property var pluginService: null

    // DMS includes disabled but physically connected heads in this map.
    function panelShouldBeEnabled(locked, greeter, outputs) {
        const serials = new Set(Object.values(outputs)
            .filter(o => o.make === "Dell Inc." && o.model === "DELL P2725D")
            .map(o => o.serial));
        return locked || greeter || !["24CRZ64", "3S5S864"].every(s => serials.has(s));
    }

    readonly property bool panelEnabled: panelShouldBeEnabled(IdleService.isShellLocked, SessionData.isGreeterMode, DisplayConfigState.outputs)
    onPanelEnabledChanged: enforce()

    function enforce() {
        const panel = DisplayConfigState.outputs["eDP-1"];
        if (!CompositorService.isNiri || !panel || panel.enabled === panelEnabled || change.running)
            return;
        change.running = true;
    }

    Process {
        id: change
        command: ["@NIRI@", "msg", "output", "eDP-1", root.panelEnabled ? "on" : "off"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                console.warn("Framework panel change failed:", exitCode);
            else
                WlrOutputService.requestState();
        }
    }

    Connections {
        target: DisplayConfigState
        function onOutputsChanged() { root.enforce(); }
    }
    Component.onCompleted: enforce()
}
