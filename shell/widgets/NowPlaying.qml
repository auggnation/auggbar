import QtQuick
import QtQuick.Layouts
import ".."

// Now playing (MPRIS) — play/pause, a scrolling "Title — Artist" ticker and
// next. Shown only while a player is active.
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: shell.npActive
    readonly property var settingsSchema: [
        { key: "maxWidth", label: "Ticker width", type: "number", default: 120, min: 60, max: 480, step: 20, suffix: " px" }
    ]
    readonly property real infoW: Math.max(56, Math.min(shell.barOpt("nowplaying", "maxWidth", 120), scroll.implicitWidth))

    implicitWidth: row.implicitWidth + 16
    implicitHeight: theme.barHeight - 6
    radius: 9
    color: theme.cardFill
    border.width: 1
    border.color: theme.cardBorder

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6

        BarButton {
            Layout.alignment: Qt.AlignVCenter
            glyph: w.shell.npPlaying ? "" : ""
            glyphSize: 13
            hPad: 5
            implicitHeight: w.theme.barHeight - 12
            onClicked: w.shell.npCmd("playpause")
        }

        // Single line. When it's wider than the widget the text marches
        // leftwards like a news ticker; a duplicate copy queued a gap behind
        // it makes the loop seamless.
        Item {
            id: viewport
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: w.infoW
            Layout.preferredHeight: scroll.implicitHeight
            clip: true

            readonly property real marqueeGap: 48
            readonly property real marqueeSpeed: 38   // logical px per second
            readonly property bool marqueeOn: w.shell.npActive && scroll.implicitWidth > width + 2

            Row {
                id: strip
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                spacing: viewport.marqueeGap
                Text {
                    id: scroll
                    text: w.shell.npText()
                    color: w.theme.barText
                    font.family: w.theme.fontFamily
                    font.pixelSize: w.theme.fontSize - 1
                    onTextChanged: { strip.x = 0; marquee.restart() }
                }
                // Second copy — hides the wrap-around seam.
                Text {
                    visible: viewport.marqueeOn
                    text: scroll.text
                    color: scroll.color
                    font.family: scroll.font.family
                    font.pixelSize: scroll.font.pixelSize
                }
            }

            NumberAnimation {
                id: marquee
                target: strip
                property: "x"
                from: 0
                to: -(scroll.implicitWidth + viewport.marqueeGap)
                running: viewport.marqueeOn
                loops: Animation.Infinite
                duration: Math.max(4000, Math.round((scroll.implicitWidth + viewport.marqueeGap) / viewport.marqueeSpeed * 1000))
                easing.type: Easing.Linear
                onRunningChanged: if (!running) strip.x = 0
            }
        }

        BarButton {
            Layout.alignment: Qt.AlignVCenter
            glyph: ""
            glyphSize: 13
            hPad: 5
            implicitHeight: w.theme.barHeight - 12
            onClicked: w.shell.npCmd("next")
        }
    }
}
