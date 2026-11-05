import QtQuick
import Quickshell

ShellRoot {
    property ScriptModel model: ScriptModel {
        values: [{ name: "test" }]
        comparisonMode: ObjectComparison.Structure
    }
}
