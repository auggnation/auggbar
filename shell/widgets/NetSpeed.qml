import QtQuick
import ".."

// NetSpeed — down/up rate of the default-route interface. Fixed width, so the
// items around it never shift when the rates change. Each arrow sits 2 px
// away from its number.
Item {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: true

    readonly property int arrowGap: 2
    readonly property int pixel: theme.fontSize - 3
    readonly property bool active: !!shell.netIface && shell.netIface !== "-"

    // Widest possible readout: two (arrow + gap + number) groups and the space between them.
    implicitWidth: Math.ceil(2 * (arrowMetrics.advanceWidth("") + w.arrowGap
        + valueMetrics.advanceWidth(shell.fmtBpsFixed(0))) + valueMetrics.advanceWidth(" ")) + 8
    implicitHeight: theme.barHeight - 8

    FontMetrics {
        id: arrowMetrics
        font.family: w.theme.glyphFont
        font.pixelSize: w.pixel
    }
    FontMetrics {
        id: valueMetrics
        font.family: w.theme.fontFamily
        font.pixelSize: w.pixel
    }

    Row {
        anchors.centerIn: parent
        spacing: 0
        visible: w.active

        Text {
            text: ""
            color: w.theme.tones[0]
            font.family: w.theme.glyphFont
            font.pixelSize: w.pixel
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: w.arrowGap; height: 1 }
        Text {
            text: w.shell.fmtBpsFixed(w.shell.netDown)
            color: w.theme.tones[0]
            font.family: w.theme.fontFamily
            font.pixelSize: w.pixel
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: valueMetrics.advanceWidth(" "); height: 1 }
        Text {
            text: ""
            color: w.theme.tones[0]
            font.family: w.theme.glyphFont
            font.pixelSize: w.pixel
            anchors.verticalCenter: parent.verticalCenter
        }
        Item { width: w.arrowGap; height: 1 }
        Text {
            text: w.shell.fmtBpsFixed(w.shell.netUp)
            color: w.theme.tones[0]
            font.family: w.theme.fontFamily
            font.pixelSize: w.pixel
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
