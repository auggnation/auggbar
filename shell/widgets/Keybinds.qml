import QtQuick
import ".."

// Keybinds — a small keyboard button that opens the keybinds cheat sheet.
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: true

    implicitWidth: glyph.implicitWidth + 20
    implicitHeight: theme.barHeight - 6
    radius: 9
    color: (hover.hovered || shell.keybindsOpen) ? theme.hoverFill : theme.pillFill
    border.width: 1
    border.color: shell.keybindsOpen ? theme.accent : theme.pillBorder
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
        id: glyph
        anchors.centerIn: parent
        text: ""
        color: w.shell.keybindsOpen ? theme.accent : theme.tones[2]
        font.family: theme.fontFamily
        font.pixelSize: 15
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: w.shell.toggleKeybinds()
    }
}
