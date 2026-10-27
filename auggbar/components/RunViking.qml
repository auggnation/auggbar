import QtQuick
import Quickshell
import Quickshell.Io

// RunViking — a CPU-load-driven running viking for the Quickshell bar.
//
// Inspired by RunCat for GNOME Shell ("RunCat", runcat@kolesnikov.se) by
// Sergei Kolesnikov (win0err) — https://github.com/win0err/gnome-runcat (GPL-3.0).
// RunViking is an independent Quickshell re-implementation; full credit for the
// original "the pet runs faster as the CPU works harder" idea goes to RunCat.
//
// The host may pass its theme object (e.g. `hostTheme: theme`) so the widget and
// its settings popup follow the desktop palette. If no theme is given, sensible
// defaults are used. Right-click or Alt+click the viking to open settings.
Item {
    id: root
    implicitWidth: row.implicitWidth
    implicitHeight: 18

    // Host theme (optional). Expected props: accent, background, barText,
    // barBackground, radius, popupRadius, fontFamily, fontSize.
    property QtObject hostTheme: null

    // Default system monitor: btop++ (the C++ btop) in a Ghostty window.
    // ~/.local/bin/augment-sysmon does exactly the same thing and stays as
    // the desktop-wide shortcut for it.
    readonly property string defaultMonitorCommand: "ghostty --title=btop++ -e btop"

    // ---- persisted settings (survive restarts / reloads) ----
    PersistentProperties {
        id: cfg
        property int idleThreshold: 0
        property string displayMode: "character-only" // character-only | percentage-only | character-and-percentage
        property bool invertSpeed: false
        property bool smoothSpeed: true
        property string monitorCommand: root.defaultMonitorCommand
        property string appearance: "auto" // auto | dark | light
    }

    // ---- theme-derived palette ----
    readonly property bool themeIsDark: {
        if (!hostTheme || !hostTheme.background) return true
        var c = hostTheme.background
        return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) < 0.5
    }
    readonly property bool darkMode: cfg.appearance === "dark" ? true
        : (cfg.appearance === "light" ? false : themeIsDark)

    readonly property color accent: (hostTheme && hostTheme.accent) ? hostTheme.accent : "#7aa2f7"
    readonly property color fg: darkMode
        ? ((hostTheme && hostTheme.barText) ? hostTheme.barText : "#a9b1d6")
        : "#1c1815"
    readonly property color panel: darkMode
        ? ((hostTheme && hostTheme.barBackground) ? hostTheme.barBackground : "#1a1b26")
        : "#f4f4f6"
    readonly property color track: Qt.rgba(fg.r, fg.g, fg.b, darkMode ? 0.14 : 0.10)
    readonly property color trackBorder: Qt.rgba(fg.r, fg.g, fg.b, 0.22)
    readonly property color onAccent: darkMode ? Qt.rgba(0, 0, 0, 0.75) : "#ffffff"
    readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
    readonly property int radius: (hostTheme && hostTheme.radius) ? hostTheme.radius : 10
    readonly property string fontFamily: (hostTheme && hostTheme.fontFamily) ? hostTheme.fontFamily : "sans-serif"
    readonly property int fontSize: (hostTheme && hostTheme.fontSize) ? hostTheme.fontSize : 12

    property int frame: 0
    property real cpu: 0
    property real shownCpu: 0
    property bool settingsOpen: false

    // Sprite + helper locations. Overridable so a host (e.g. the Omarchy plugin
    // wrapper) can point at plugin-local copies instead of the shell dir.
    property string spriteDir: Quickshell.shellDir + "/viking/png"
    property string cpuScript: Quickshell.shellDir + "/scripts/cpu-percent.sh"
    readonly property string base: spriteDir

    property var frames: [
        root.base + "/active-0.png",
        root.base + "/active-1.png",
        root.base + "/active-2.png",
        root.base + "/active-3.png",
        root.base + "/active-4.png"
    ]
    readonly property string idleFrame: root.base + "/idle.png"

    readonly property real effCpu: cfg.invertSpeed ? (100 - shownCpu) : shownCpu
    readonly property bool running: shownCpu > cfg.idleThreshold

    // Migrate the old defaults: plasma-systemmonitor is no longer used, and
    // the previous default is now spelled out as btop++ so the setting shows
    // what actually runs.
    Component.onCompleted: {
        if (cfg.monitorCommand === "plasma-systemmonitor")
            cfg.monitorCommand = root.defaultMonitorCommand
        if (cfg.monitorCommand === "auggment-sysmon")
            cfg.monitorCommand = root.defaultMonitorCommand
        console.log("RunViking: loaded")
    }

    // ---- CPU sampling ----
    Process {
        id: cpuProc
        command: ["bash", root.cpuScript]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim())
                root.cpu = isNaN(v) ? 0 : v
            }
        }
    }
    Timer {
        interval: 2000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!cpuProc.running) cpuProc.running = true
    }

    // ---- smoothing towards target ----
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (cfg.smoothSpeed) root.shownCpu += (root.cpu - root.shownCpu) * 0.25
            else root.shownCpu = root.cpu
        }
    }

    // ---- animation ----
    Timer {
        id: animTimer
        interval: Math.max(90, 420 - root.effCpu * 3.5)
        running: true; repeat: true
        onTriggered: if (root.running) root.frame = (root.frame + 1) % root.frames.length
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Image {
            id: icon
            width: 18; height: 18; smooth: false; fillMode: Image.PreserveAspectFit
            source: root.running ? root.frames[root.frame % root.frames.length] : root.idleFrame
            onStatusChanged: if (status === Image.Error) console.log("RunViking: image error " + source)
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            visible: cfg.displayMode !== "character-only"
            text: Math.round(root.shownCpu) + "%"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton || (mouse.modifiers & Qt.AltModifier))
                root.settingsOpen = !root.settingsOpen
            else
                Quickshell.execDetached(["bash", "-lc", cfg.monitorCommand])
        }
    }

    // ---------- settings popup (right-click / Alt+click) ----------
    PopupWindow {
        id: popup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        visible: root.settingsOpen
        grabFocus: true
        color: "transparent"
        implicitWidth: 330
        implicitHeight: body.implicitHeight + 24

        Rectangle {
            anchors.fill: parent
            color: root.panel
            border.color: root.accent
            border.width: 1
            radius: root.radius

            Column {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 10

                Text {
                    text: "\u2694 RunViking"
                    color: root.accent
                    font.bold: true
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize + 2
                }
                Text {
                    text: "Inspired by RunCat for GNOME Shell (win0err)"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize - 2
                }

                // 1) idle threshold
                Column {
                    spacing: 3
                    width: parent.width
                    Text {
                        text: "Idle threshold: " + cfg.idleThreshold + "%"
                        color: root.fg; font.family: root.fontFamily; font.pixelSize: root.fontSize
                    }
                    Rectangle {
                        id: track
                        width: parent.width; height: 6; radius: 3; color: root.track
                        Rectangle {
                            width: track.width * cfg.idleThreshold / 100
                            height: parent.height; radius: 3; color: root.accent
                        }
                        MouseArea {
                            anchors.fill: parent
                            function setFromX(x) {
                                cfg.idleThreshold = Math.max(0, Math.min(100, Math.round(x / track.width * 100)))
                            }
                            onPressed: (m) => setFromX(m.x)
                            onPositionChanged: (m) => { if (pressed) setFromX(m.x) }
                        }
                    }
                }

                // 2) displaying items
                Column {
                    spacing: 3
                    width: parent.width
                    Text { text: "Display"; color: root.fg; font.family: root.fontFamily; font.pixelSize: root.fontSize }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [
                                ["character-only", "Viking"],
                                ["percentage-only", "%"],
                                ["character-and-percentage", "Both"]
                            ]
                            delegate: Rectangle {
                                width: 92; height: 24; radius: 6
                                color: cfg.displayMode === modelData[0] ? root.accent : root.track
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData[1]
                                    color: cfg.displayMode === modelData[0] ? root.onAccent : root.fg
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 1
                                }
                                MouseArea { anchors.fill: parent; onClicked: cfg.displayMode = modelData[0] }
                            }
                        }
                    }
                }

                // 3) invert speed
                Row {
                    spacing: 8
                    Rectangle {
                        width: 36; height: 20; radius: 10
                        color: cfg.invertSpeed ? root.accent : root.track
                        Rectangle {
                            width: 16; height: 16; radius: 8; color: root.panel; y: 2
                            x: cfg.invertSpeed ? parent.width - 18 : 2
                        }
                        MouseArea { anchors.fill: parent; onClicked: cfg.invertSpeed = !cfg.invertSpeed }
                    }
                    Text {
                        text: "Invert speed"
                        color: root.fg; font.family: root.fontFamily; font.pixelSize: root.fontSize
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // 4) smooth speed changes
                Row {
                    spacing: 8
                    Rectangle {
                        width: 36; height: 20; radius: 10
                        color: cfg.smoothSpeed ? root.accent : root.track
                        Rectangle {
                            width: 16; height: 16; radius: 8; color: root.panel; y: 2
                            x: cfg.smoothSpeed ? parent.width - 18 : 2
                        }
                        MouseArea { anchors.fill: parent; onClicked: cfg.smoothSpeed = !cfg.smoothSpeed }
                    }
                    Text {
                        text: "Smooth speed changes"
                        color: root.fg; font.family: root.fontFamily; font.pixelSize: root.fontSize
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // 5) appearance (theme)
                Column {
                    spacing: 3
                    width: parent.width
                    Text { text: "Appearance"; color: root.fg; font.family: root.fontFamily; font.pixelSize: root.fontSize }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [
                                ["auto", "Theme"],
                                ["dark", "Dark"],
                                ["light", "Light"]
                            ]
                            delegate: Rectangle {
                                width: 92; height: 24; radius: 6
                                color: cfg.appearance === modelData[0] ? root.accent : root.track
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData[1]
                                    color: cfg.appearance === modelData[0] ? root.onAccent : root.fg
                                    font.family: root.fontFamily; font.pixelSize: root.fontSize - 1
                                }
                                MouseArea { anchors.fill: parent; onClicked: cfg.appearance = modelData[0] }
                            }
                        }
                    }
                }

                // 6) custom system monitor command
                Column {
                    spacing: 3
                    width: parent.width
                    Text { text: "System monitor command"; color: root.fg; font.family: root.fontFamily; font.pixelSize: root.fontSize }
                    Rectangle {
                        width: parent.width; height: 28; radius: 6
                        color: root.track; border.color: root.trackBorder; border.width: 1
                        TextInput {
                            id: cmdInput
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.fg; font.family: root.fontFamily; font.pixelSize: root.fontSize
                            clip: true
                            onEditingFinished: cfg.monitorCommand = text
                            Component.onCompleted: text = cfg.monitorCommand
                        }
                    }
                }

                Rectangle {
                    width: parent.width; height: 26; radius: 6
                    color: closeMa.containsMouse ? root.accent : root.track
                    Text {
                        anchors.centerIn: parent
                        text: "Close"
                        color: closeMa.containsMouse ? root.onAccent : root.fg
                        font.family: root.fontFamily; font.pixelSize: root.fontSize
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.settingsOpen = false
                    }
                }
            }
        }
    }
}
