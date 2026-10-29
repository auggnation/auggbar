import QtQuick
import ".."

// Separator — thin vertical divider.
Rectangle {
    required property var shell
    property bool shown: true
    implicitWidth: 1
    implicitHeight: 16
    color: Theme.cardBorder
}
