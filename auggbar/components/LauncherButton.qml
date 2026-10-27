import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// LauncherButton — the Augment menu button for the Quickshell bar.
//
// Clicking it opens (or closes) the desktop launcher (hyprlauncher). The
// button also owns the Super+Space shortcut: it keeps a managed Hyprland
// bind file in sync and reloads Hyprland when the shortcut changes, so the
// button and the key can never drift apart.
//
// The host may pass its theme object (e.g. `hostTheme: theme`) so the button
// and its settings popup follow the desktop palette. Right-click or
// Alt+click the button to open the settings.
Item {
    id: root
    implicitWidth: btn.implicitWidth
    implicitHeight: btn.implicitHeight

    // Host theme (optional). Expected props: accent, barText, barBackground,
    // radius, fontFamily, fontSize, barHeight.
    property QtObject hostTheme: null

    readonly property string home: Quickshell.env("HOME")
    readonly property string defaultLauncher: root.home + "/.local/bin/augment-launcher"
    readonly property string bindFile: root.home + "/.config/hypr/augment-launcher.lua"

    // ---- persisted settings (survive restarts / reloads) ----
    PersistentProperties {
        id: cfg
        property string launcherCommand: root.defaultLauncher
        property bool superSpace: true
        property bool superD: true
    }

    // ---- theme-derived palette ----
    readonly property color accent: (hostTheme && hostTheme.accent) ? hostTheme.accent : "#7aa2f7"
    readonly property color fg: (hostTheme && hostTheme.barText) ? hostTheme.barText : "#a9b1d6"
    readonly property color muted: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
    readonly property color hoverFill: (hostTheme && hostTheme.hoverFill)
        ? hostTheme.hoverFill : Qt.rgba(fg.r, fg.g, fg.b, 0.08)
    readonly property color panel: (hostTheme && hostTheme.barBackground)
        ? hostTheme.barBackground : "#1a1b26"
    readonly property color track: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
    readonly property color trackBorder: Qt.rgba(fg.r, fg.g, fg.b, 0.22)
    readonly property color accentText: "#ffffff"
    readonly property int radius: (hostTheme && hostTheme.radius) ? hostTheme.radius : 10
    readonly property string fontFamily: (hostTheme && hostTheme.fontFamily) ? hostTheme.fontFamily : "sans-serif"
    readonly property int fontSize: (hostTheme && hostTheme.fontSize) ? hostTheme.fontSize : 12
    readonly property int barHeight: (hostTheme && hostTheme.barHeight) ? hostTheme.barHeight : 26

    // nf-fa-th_large — an app grid, the usual "menu" glyph.
    readonly property string glyph: "\uf00a"

    // The command the launcher is started with (exposed for the shell's
    // "launcher" IPC target).
    readonly property string command: cfg.launcherCommand

    property bool settingsOpen: false
    property bool busy: false

    function run(cmd) { Quickshell.execDetached(["bash", "-lc", cmd]) }

    // ------------------------------------------------------------ launcher
    // Opens the launcher. The helper script starts the hyprlauncher daemon
    // if it is not running yet, so a cold session still gets a launcher.
    function toggle() {
        root.busy = true
        root.run("'" + cfg.launcherCommand + "'")
        busyTimer.restart()
    }

    Timer {
        id: busyTimer
        interval: 1200
        repeat: false
        onTriggered: root.busy = false
    }

    // ----------------------------------------------------------- shortcut
    // The bind lives in a managed file that Hyprland dofile()s, so the
    // shortcut can be changed from here without ever touching hyprland.lua.
    function bindFileContent() {
        var lines = [
            "-- Managed by the Augment Quickshell launcher button",
            "-- (~/.config/quickshell/components/LauncherButton.qml).",
            "-- Rewritten automatically - do not edit by hand.",
            'local mainMod = "SUPER"',
            'local launcher = "' + cfg.launcherCommand + '"',
            ""
        ]
        if (cfg.superSpace)
            lines.push('hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(launcher))')
        if (cfg.superD)
            lines.push('hl.bind(mainMod .. " + D",     hl.dsp.exec_cmd(launcher))')
        return lines.join("\n") + "\n"
    }

    // Writes the managed file and reloads Hyprland, but only when the content
    // actually changed - a reload on every bar start would be wasteful.
    function applyShortcut() {
        var content = root.bindFileContent()
        var script =
            "f=\"$HOME/.config/hypr/augment-launcher.lua\"; " +
            "t=$(mktemp); " +
            "cat > \"$t\" <<'AUGMENT_LAUNCHER_EOF'\n" + content + "AUGMENT_LAUNCHER_EOF\n" +
            "mkdir -p \"$HOME/.config/hypr\"; " +
            "if cmp -s \"$t\" \"$f\"; then rm -f \"$t\"; else " +
            "cp \"$t\" \"$f\" && rm -f \"$t\" && hyprctl reload; fi"
        writeProc.command = ["bash", "-lc", script]
        if (!writeProc.running) writeProc.running = true
    }

    Process { id: writeProc }

    Component.onCompleted: {
        root.applyShortcut()
        console.log("LauncherButton: loaded")
    }

    // -------------------------------------------------------------- button
    Rectangle {
        id: btn
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 30
        implicitHeight: root.barHeight - 8
        radius: root.radius
        color: (hover.hovered || root.busy) ? root.hoverFill : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: root.glyph
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: root.fontSize + 3
        }
        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function (m) {
                if (m.button === Qt.RightButton || (m.modifiers & Qt.AltModifier))
                    root.settingsOpen = !root.settingsOpen
                else
                    root.toggle()
            }
        }
    }

    // ------------------------------------------------- settings (right click)
    PopupWindow {
        id: popup
        anchor.item: root
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        visible: root.settingsOpen
        grabFocus: true
        color: "transparent"
        implicitWidth: 340
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
                    text: "\uf00a  Launcher"
                    color: root.accent
                    font.bold: true
                    font.family: root.fontFamily
                    font.pixelSize: root.fontSize + 2
                }

                // 1) launcher command
                Column {
                    spacing: 3
                    width: parent.width
                    Text {
                        text: "Launcher command"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize
                    }
                    Rectangle {
                        width: parent.width; height: 28; radius: 6
                        color: root.track; border.color: root.trackBorder; border.width: 1
                        TextInput {
                            id: cmdInput
                            anchors.fill: parent
                            anchors.leftMargin: 8; anchors.rightMargin: 8
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: root.fontSize
                            clip: true
                            onEditingFinished: {
                                if (text.trim() !== "") {
                                    cfg.launcherCommand = text.trim()
                                    root.applyShortcut()
                                } else {
                                    text = cfg.launcherCommand
                                }
                            }
                            Component.onCompleted: text = cfg.launcherCommand
                        }
                    }
                }

                // 2) Super+Space
                Row {
                    spacing: 8
                    Rectangle {
                        width: 36; height: 20; radius: 10
                        color: cfg.superSpace ? root.accent : root.track
                        Rectangle {
                            width: 16; height: 16; radius: 8; color: root.panel; y: 2
                            x: cfg.superSpace ? parent.width - 18 : 2
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { cfg.superSpace = !cfg.superSpace; root.applyShortcut() }
                        }
                    }
                    Text {
                        text: "Super + Space opens the launcher"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // 3) Super+D
                Row {
                    spacing: 8
                    Rectangle {
                        width: 36; height: 20; radius: 10
                        color: cfg.superD ? root.accent : root.track
                        Rectangle {
                            width: 16; height: 16; radius: 8; color: root.panel; y: 2
                            x: cfg.superD ? parent.width - 18 : 2
                            Behavior on x { NumberAnimation { duration: 120 } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { cfg.superD = !cfg.superD; root.applyShortcut() }
                        }
                    }
                    Text {
                        text: "Super + D opens the launcher"
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: root.fontSize
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // 4) apply / close
                Row {
                    spacing: 6
                    width: parent.width

                    Rectangle {
                        width: (parent.width - 6) / 2; height: 26; radius: 6
                        color: applyMa.containsMouse ? root.accent : root.track
                        Text {
                            anchors.centerIn: parent
                            text: "Apply shortcut"
                            color: applyMa.containsMouse ? root.accentText : root.fg
                            font.family: root.fontFamily
                            font.pixelSize: root.fontSize
                        }
                        MouseArea {
                            id: applyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.applyShortcut()
                        }
                    }

                    Rectangle {
                        width: (parent.width - 6) / 2; height: 26; radius: 6
                        color: closeMa.containsMouse ? root.accent : root.track
                        Text {
                            anchors.centerIn: parent
                            text: "Close"
                            color: closeMa.containsMouse ? root.accentText : root.fg
                            font.family: root.fontFamily
                            font.pixelSize: root.fontSize
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
}
