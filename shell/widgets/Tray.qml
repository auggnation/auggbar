import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray

// Tray — system tray icons. Left click activates, middle click secondary,
// scroll forwards to the app.
Row {
    required property var shell
    property bool shown: SystemTray.items.values.length > 0
    spacing: 7
    Repeater {
        model: SystemTray.items
        delegate: IconImage {
            id: trayIcon
            required property var modelData
            source: modelData.icon
            implicitSize: 16
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (m) {
                    if (m.button === Qt.LeftButton) trayIcon.modelData.activate()
                    else if (m.button === Qt.MiddleButton) trayIcon.modelData.secondaryActivate()
                }
                onWheel: function (w) { trayIcon.modelData.scroll(w.angleDelta.y, false) }
            }
        }
    }
}
