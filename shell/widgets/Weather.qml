import QtQuick
import ".."

// Weather — current temp + condition. Click for the forecast, right-click
// for settings. Hidden until the first successful fetch.
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: shell.wxOk
    function openSettings() { w.shell.wxToggleSet() }
    readonly property bool active: hover.hovered || shell.wxOpen || shell.wxSetOpen

    implicitHeight: theme.barHeight - 6
    implicitWidth: row.implicitWidth + 18
    radius: theme.radius
    color: w.active ? theme.hoverFill : theme.cardFill
    border.width: 1
    border.color: w.active ? theme.accent : theme.cardBorder
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: w.shell.wxTemp
            color: theme.barText
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: w.shell.wxIcon
            color: theme.accent
            font.family: theme.fontFamily
            font.pixelSize: 15
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (m) {
            if (m.button === Qt.RightButton) w.shell.wxToggleSet()
            else w.shell.wxToggle()
        }
    }
}
