import QtQuick
import Quickshell.Hyprland
import ".."

// Workspaces — one pill per Hyprland workspace; click to switch.
Row {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: true
    spacing: 4

    Repeater {
        model: Hyprland.workspaces
        delegate: Rectangle {
            required property var modelData
            readonly property bool act: modelData.focused
            readonly property bool show: modelData.id >= 1
            visible: show
            width: show ? 24 : 0
            height: show ? 20 : 0
            radius: 6
            color: act ? theme.accent : (modelData.occupied ? theme.normalFill : "transparent")
            border.width: (!act && modelData.occupied) ? 1 : 0
            border.color: theme.cardBorder
            Behavior on color { ColorAnimation { duration: 140 } }
            Text {
                anchors.centerIn: parent
                text: modelData.name !== "" ? modelData.name : String(modelData.id)
                color: act ? theme.barBackground : theme.textMuted
                font.family: theme.fontFamily
                font.pixelSize: 12
                font.bold: act
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.activate()
            }
        }
    }
}
