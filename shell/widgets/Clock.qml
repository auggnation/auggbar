import QtQuick
import Quickshell
import ".."

// Clock — date + time. Left click opens the calendar. Calendar accounts
// are reached from the clock's settings (right-click / Alt+click).
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: true
    readonly property var settingsSchema: [
        { key: "use24h", label: "24-hour time", type: "bool", default: true },
        { key: "showDate", label: "Show date", type: "bool", default: true },
        { key: "accounts", label: "Calendar accounts…", type: "action" }
    ]
    function settingsAction(key) { if (key === "accounts") w.shell.calOpenAuth() }
    readonly property bool use24h: shell.barOpt("clock", "use24h", true)
    readonly property bool showDate: shell.barOpt("clock", "showDate", true)
    readonly property bool open: shell.calOpen || shell.calAuthOpen

    implicitWidth: row.implicitWidth + 24
    implicitHeight: theme.barHeight - 6
    radius: 9
    color: (hover.hovered || w.open) ? theme.hoverFill : theme.cardFill
    border.width: 1
    border.color: w.open ? theme.accent : theme.cardBorder
    Behavior on color { ColorAnimation { duration: 120 } }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    HoverHandler { id: hover }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 9
        Text {
            visible: w.showDate
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            color: theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
        }
        Rectangle {
            visible: w.showDate
            anchors.verticalCenter: parent.verticalCenter
            width: 1; height: 13
            color: theme.cardBorder
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, w.use24h ? "HH:mm" : "h:mm AP")
            color: theme.accent
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize + 2
            font.bold: true
        }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton || (mouse.modifiers & Qt.AltModifier)) w.shell.calOpenAuth()
            else w.shell.calOpenPanel()
        }
    }
}
