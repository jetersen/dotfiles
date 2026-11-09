pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.DCommon.Widgets

PluginComponent {
    id: root
    layerNamespacePlugin: "workTailnet"
    popoutWidth: 320
    popoutHeight: showSignIn ? 210 : 160
    property var connectionState: ({mode: "off", connected: false})
    property string error: ""
    readonly property string popupTitle: connectionState.tailnetName || "Work tailnet"
    readonly property bool autoAvailable: @auto-available@
    readonly property var modeChoices: autoAvailable ? ["on", "off", "auto"] : ["on", "off"]
    readonly property bool showSignIn: connectionState.hasProfile === false && !error
    readonly property string stateIcon: error ? "error" : connectionState.connected ? "work" : "work_off"
    readonly property color stateColor: error ? Theme.error : connectionState.connected ? Theme.primary : Theme.surfaceVariantText

    function choose(mode) {
        if (action.running) return;
        action.command = ["@work-tailnet@", mode];
        action.running = true;
    }

    Process {
        id: status
        command: ["@work-tailnet@", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.connectionState = JSON.parse(text);
                    root.error = root.connectionState.error || "";
                } catch (e) { root.error = "Work tailnet service unavailable"; }
            }
        }
        onExited: (code) => {
            if (code !== 0) root.error = "Work tailnet service unavailable";
        }
    }
    Process {
        id: action
        onExited: { status.running = true; }
    }
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: { if (!status.running) status.running = true; }
    }

    horizontalBarPill: Component {
        DIcon {
            name: root.stateIcon
            size: Theme.iconSize - 6
            color: root.stateColor
            filled: root.connectionState.connected
        }
    }
    verticalBarPill: root.horizontalBarPill
    popoutContent: Component {
        ColumnLayout {
            spacing: Theme.spacingM
            StyledText { text: root.popupTitle; font.pixelSize: Theme.fontSizeLarge }
            StyledText {
                Layout.fillWidth: true
                text: root.error || (root.connectionState.connected ? "Connected" :
                    root.showSignIn ? "Sign in to the work tailnet" :
                    root.connectionState.mode === "on" && root.connectionState.backend !== "NeedsLogin" ? "Connecting…" : "Disconnected")
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Repeater {
                    model: root.modeChoices
                    DButton {
                        required property string modelData
                        text: (root.connectionState.mode === modelData ? "✓ " : "") +
                            modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        onClicked: root.choose(modelData)
                    }
                }
            }
            DButton {
                visible: root.showSignIn
                text: "Sign in"
                onClicked: Quickshell.execDetached(["@terminal@", "-e", "@work-tailnet@", "login"])
            }
        }
    }
}
