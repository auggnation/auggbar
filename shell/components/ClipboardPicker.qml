import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// ClipboardPicker — clipboard history (cliphist) in the same style as the app
// launcher. Super+V opens it; Enter puts the chosen entry back on the
// clipboard; Delete removes it from the history; Esc closes.
// History is collected at login by `wl-paste --watch cliphist store`.
Item {
    id: root
    readonly property QtObject theme: Theme
    property bool opened: false
    property string query: ""
    property int current: 0
    property var items: []                       // [{ id, text }]

    function toggle() { if (root.opened) root.close(); else root.open() }
    function open() {
        root.query = ""
        root.current = 0
        root.opened = true
        loader.running = true
    }
    function close() { root.opened = false }

    Process {
        id: loader
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = String(this.text).split("\n")
                for (var i = 0; i < lines.length && out.length < 300; i++) {
                    var l = lines[i]
                    var t = l.indexOf("\t")
                    if (t > 0) out.push({ id: l.slice(0, t), text: l.slice(t + 1) })
                }
                root.items = out
            }
        }
    }

    readonly property var results: {
        var q = root.query.trim().toLowerCase()
        if (q === "") return root.items
        return root.items.filter(function (x) { return x.text.toLowerCase().indexOf(q) >= 0 })
    }

    Process { id: runner }
    function choose(e) {
        if (!e) return
        root.close()
        runner.command = ["bash", "-c", "cliphist decode \"$1\" | wl-copy", "_", e.id]
        runner.running = true
    }
    function forget(e) {
        if (!e) return
        runner.command = ["bash", "-c", "cliphist delete-query \"$1\"", "_", e.text]
        runner.running = true
        root.items = root.items.filter(function (x) { return x.id !== e.id })
    }

    Loader {
        active: root.opened
        sourceComponent: PanelWindow {
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(640, parent.width - 40)
                height: Math.min(520, parent.height - 80)
                radius: root.theme.popupRadius
                color: root.theme.panelBackground
                border.width: 1
                border.color: root.theme.outlineVariant

                Grain {}
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    Text {
                        text: "Clipboard history"
                        color: root.theme.barText
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fontSize + 3
                        font.bold: true
                    }

                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 2
                        model: root.results
                        currentIndex: root.current
                        boundsBehavior: Flickable.StopAtBounds
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            width: list.width
                            height: 40
                            radius: 8
                            color: root.current === row.index ? root.theme.accentSoft : (hover.hovered ? root.theme.hoverFill : "transparent")
                            border.width: root.current === row.index ? 1 : 0
                            border.color: root.theme.accent
                            Text {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                verticalAlignment: Text.AlignVCenter
                                text: row.modelData.text.replace(/\s+/g, " ")
                                color: root.theme.barText
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fontSize
                                elide: Text.ElideRight
                            }
                            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: function (m) {
                                    if (m.button === Qt.RightButton) root.forget(row.modelData)
                                    else root.choose(row.modelData)
                                }
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: root.query !== "" ? "No matches" : "Nothing copied yet"
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSize
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 42
                        radius: 21
                        color: root.theme.surfaceHigh
                        border.width: 1
                        border.color: search.activeFocus ? root.theme.accent : root.theme.outlineVariant
                        TextInput {
                            id: search
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.theme.barText
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSize + 1
                            selectByMouse: true
                            clip: true
                            focus: true
                            onTextChanged: { root.query = text; root.current = 0 }
                            Component.onCompleted: forceActiveFocus()
                            Keys.onPressed: function (ev) {
                                var n = list.count
                                if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true }
                                else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) { if (n) root.current = (root.current + 1) % n; ev.accepted = true }
                                else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) { if (n) root.current = (root.current - 1 + n) % n; ev.accepted = true }
                                else if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && n) { root.choose(root.results[root.current]); ev.accepted = true }
                                else if (ev.key === Qt.Key_Delete && n) { root.forget(root.results[root.current]); ev.accepted = true }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            visible: search.text === ""
                            text: "Search clipboard…"
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSize + 1
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggle() }
    }
}
