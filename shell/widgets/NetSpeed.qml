import QtQuick
import ".."

// NetSpeed — down/up rate of the default-route interface. Fixed width, so the
// items around it never shift when the rates change.
Item {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: true

    implicitWidth: Math.max(metrics.advanceWidth(shell.netSpeedSample()), label.implicitWidth) + 8
    implicitHeight: theme.barHeight - 8

    FontMetrics {
        id: metrics
        font.family: w.theme.fontFamily
        font.pixelSize: w.theme.fontSize - 3
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: w.shell.netSpeedText()
        visible: text !== ""
        color: w.theme.textMuted
        font.family: w.theme.fontFamily
        font.pixelSize: w.theme.fontSize - 3
    }
}
