import QtQuick

// Bluetooth — click for devices, right-click for settings.
BarButton {
    tone: 4
    required property var shell
    property bool shown: true
    function openSettings() { shell.btToggle(true) }
    glyph: shell.btGlyph(); glyphSize: 15
    glyphColor: (shell.btOn && shell.btConnectedCount() > 0) ? fg : (shell.btOn ? fg : theme.textMuted)
    highlight: shell.btOpen
    onClicked: shell.btToggle(false)
    onRightClicked: shell.btToggle(true)
}
