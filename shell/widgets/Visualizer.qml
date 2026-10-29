import QtQuick
import Quickshell
import Quickshell.Io
import ".."

// Visualizer — cava audio visualizer.
//
// In the bar it is a wide, short strip that only shows while music is playing
// (with a few seconds' grace between tracks). Click it to open the big
// visualizer in its own app window (title "auggbar visualizer"), which
// Hyprland tiles like any other window. Click the strip again, or close the
// window, to turn it off. cava only runs while one of the two is visible.
// Options (settings.json, plugin "cava"): pillBars, hideWhenIdle, desktop.
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme

    // ---- tunables ----
    readonly property int bandCount: 64     // bands cava produces (window view)
    readonly property int pillBars: shell.barOpt("cava", "pillBars", 24)
    readonly property bool hideWhenIdle: shell.barOpt("cava", "hideWhenIdle", true)
    readonly property bool desktopOpen: shell.barOpt("cava", "desktop", false)
    function setDesktop(on) { w.shell.barSetOpt("cava", "desktop", on) }

    readonly property var settingsSchema: [
        { key: "pillBars", label: "Bars in the bar", type: "number", default: 24, min: 8, max: 48, step: 4 },
        { key: "hideWhenIdle", label: "Hide when nothing plays", type: "bool", default: true },
        { key: "desktop", label: "Visualizer window", type: "bool", default: false }
    ]

    // ---- state ----
    property bool playing: false            // shell.npPlaying with a grace period
    property bool shown: w.playing || !w.hideWhenIdle
    property var levels: []

    Connections {
        target: w.shell
        function onNpPlayingChanged() { w.syncPlaying() }
    }
    Component.onCompleted: w.syncPlaying()
    function syncPlaying() {
        if (w.shell.npPlaying) { grace.stop(); w.playing = true }
        else grace.restart()
    }
    Timer { id: grace; interval: 4000; onTriggered: w.playing = w.shell.npPlaying }

    // The strip takes the loudest band of each group (averaging flattens the
    // peaks), then lifts quiet values a little so soft passages still move.
    function pillLevel(i) {
        var per = w.bandCount / w.pillBars, m = 0
        for (var k = Math.floor(i * per); k < Math.max(Math.floor((i + 1) * per), Math.floor(i * per) + 1); k++)
            m = Math.max(m, w.levels[k] || 0)
        return Math.pow(m, 0.7)
    }

    // Bar colour for a level: the wallpaper accent, tipping toward the
    // theme's bright foreground as it gets louder. Both come from the live
    // theme, so the visualizer recolours with every wallpaper change.
    function levelColor(lv) {
        var a = w.theme.accent, b = w.theme.brightForeground, k = Math.min(1, lv) * 0.55
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1)
    }

    // ---- cava ----
    // Low noise_reduction = fast, punchy response (77 was sluggish).
    readonly property string cavaConfig: [
        "[general]",
        "bars = " + w.bandCount,
        "framerate = 60",
        "autosens = 1",
        "[output]",
        "method = raw",
        "raw_target = /dev/stdout",
        "data_format = ascii",
        "ascii_max_range = 1000",
        "bar_delimiter = 59",
        "[smoothing]",
        "noise_reduction = 20"
    ].join("\\n")

    Process {
        id: cava
        running: w.shown || w.desktopOpen
        command: ["bash", "-c", "exec cava -p <(printf '" + w.cavaConfig + "\\n')"]
        stdout: SplitParser {
            onRead: data => {
                var tokens = data.split(";")
                var next = []
                for (var i = 0; i < w.bandCount; i++)
                    next.push(Math.max(0, Math.min(1, (parseInt(tokens[i]) || 0) / 1000)))
                w.levels = next
            }
        }
        onRunningChanged: if (!running) w.levels = []
        // cava exits if the audio server restarts; bring it back.
        onExited: if (w.shown || w.desktopOpen) restart.start()
    }
    Timer { id: restart; interval: 2000; onTriggered: cava.running = w.shown || w.desktopOpen }
    Timer { id: closedCheck; interval: 400; onTriggered: if (!win.visible && w.desktopOpen) w.setDesktop(false) }

    // ---- bar strip ----
    implicitWidth: strip.implicitWidth + 14
    implicitHeight: theme.barHeight - 6
    radius: 9
    color: (hover.hovered || w.desktopOpen) ? theme.hoverFill : theme.cardFill
    border.width: 1
    border.color: w.desktopOpen ? theme.accent : theme.cardBorder
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: strip
        anchors.centerIn: parent
        spacing: 2
        height: parent.height - 6
        Repeater {
            model: w.pillBars
            Rectangle {
                required property int index
                readonly property real lv: w.pillLevel(index)
                anchors.verticalCenter: parent.verticalCenter
                width: 3
                radius: 1.5
                // Grows from the middle, so it reads well in a short bar.
                height: Math.max(2, strip.height * lv)
                color: w.levelColor(lv)
                opacity: 0.6 + 0.4 * lv
            }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: w.setDesktop(!w.desktopOpen)
    }

    // ---- visualizer window ----
    FloatingWindow {
        id: win
        title: "auggbar visualizer"
        visible: w.desktopOpen
        implicitWidth: 900
        implicitHeight: 300
        color: w.theme.darkerBackground
        // Closed from the compositor (Super+Q etc.): remember it is off. The
        // check is deferred so the bar shutting down (which also hides the
        // window) never gets to save it as off.
        onVisibleChanged: if (!visible && w.desktopOpen) closedCheck.restart()

        Row {
            id: winRow
            anchors.fill: parent
            anchors.margins: 18
            spacing: 4
            Repeater {
                model: w.bandCount
                Item {
                    required property int index
                    width: (winRow.width - winRow.spacing * (w.bandCount - 1)) / w.bandCount
                    height: winRow.height
                    Rectangle {
                        id: bandBar
                        readonly property real lv: Math.pow(w.levels[parent.index] || 0, 0.8)
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(3, parent.height * lv)
                        radius: Math.min(4, width / 2)
                        // Bright tip at the top, accent fading out at the base.
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: w.levelColor(bandBar.lv) }
                            GradientStop { position: 1.0; color: Qt.rgba(w.theme.accent.r, w.theme.accent.g, w.theme.accent.b, 0.30) }
                        }
                    }
                }
            }
        }
        Text {
            visible: !w.shell.npPlaying
            anchors.centerIn: parent
            text: "Nothing playing"
            color: w.theme.textMuted
            font.family: w.theme.fontFamily
            font.pixelSize: w.theme.fontSize + 2
        }
    }
}
