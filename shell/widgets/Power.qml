import QtQuick
import ".."

// Power — opens the power menu (reboot / restart bar / power off / suspend).
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: true

    implicitWidth: glyph.implicitWidth + 24
    implicitHeight: theme.barHeight - 6
    radius: 9
    color: (hover.hovered || shell.powerOpen) ? theme.hoverFill : theme.cardFill
    border.width: 1
    border.color: shell.powerOpen ? theme.accent : theme.cardBorder
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
        id: glyph
        anchors.centerIn: parent
        text: ""
        color: w.shell.powerOpen ? theme.accent : theme.barText
        font.family: theme.fontFamily
        font.pixelSize: 15
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: w.shell.togglePower()
    }
}
