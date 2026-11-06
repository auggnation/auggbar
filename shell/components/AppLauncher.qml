import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."

// AppLauncher — the Quickshell app launcher, styled after the Noctalia one:
// tabs (Recent / Pinned / All), a result list, search at the bottom.
//
//   Up / Down, Tab    move            Enter   launch
//   Esc               close           Ctrl+P  pin / unpin
//   Left / Right      switch tab (while the search box is empty)
//
// Nothing is built while it is closed (the window lives in a Loader), so it
// costs nothing at idle. Usage counts, recents and pins are kept in
// ~/.local/state/auggment/launcher.json.
Item {
    id: root

    readonly property QtObject theme: Theme
    property bool opened: false
    property string query: ""
    property int tab: 0                       // 0 Recent, 1 Pinned, 2 All
    property int current: 0
    property var powerAction: function () {}  // set by the host: opens the power panel

    // persisted: { counts: {id: n}, recent: [id...], pinned: [id...] }
    property var store: ({ counts: ({}), recent: [], pinned: [] })
    readonly property string storePath: Quickshell.env("HOME") + "/.local/state/auggment/launcher.json"

    function toggle() { if (root.opened) root.close(); else root.open() }
    function open() {
        root.query = ""
        root.current = 0
        root.tab = (root.store.recent && root.store.recent.length > 0) ? 0 : 2
        root.opened = true
    }
    function close() { root.opened = false }

    FileView {
        id: file
        path: root.storePath
        blockLoading: true
        onLoaded: {
            try {
                var d = JSON.parse(file.text())
                root.store = { counts: d.counts || ({}), recent: d.recent || [], pinned: d.pinned || [] }
            } catch (e) { /* first run */ }
        }
    }
    function save() {
        file.setText(JSON.stringify(root.store))
    }

    function allApps() {
        var vals = DesktopEntries.applications.values
        var out = []
        for (var i = 0; i < vals.length; i++) if (vals[i] && !vals[i].noDisplay) out.push(vals[i])
        return out
    }
    function byId(id) {
        var vals = DesktopEntries.applications.values
        for (var i = 0; i < vals.length; i++) if (vals[i].id === id) return vals[i]
        return null
    }
    function uses(e) { return (root.store.counts && root.store.counts[e.id]) || 0 }
    function pinned(e) { return root.store.pinned.indexOf(e.id) >= 0 }

    function score(e, q) {
        var n = String(e.name || "").toLowerCase()
        var best = -1
        if (n === q) best = 100
        else if (n.indexOf(q) === 0) best = 80
        else if (n.indexOf(" " + q) >= 0) best = 70
        else if (n.indexOf(q) >= 0) best = 55
        if (best < 0) {
            var g = String(e.genericName || "").toLowerCase()
            var kw = (e.keywords || []).join(" ").toLowerCase()
            var c = String(e.comment || "").toLowerCase()
            var id = String(e.id || "").toLowerCase()
            if (g.indexOf(q) >= 0) best = 40
            else if (kw.indexOf(q) >= 0) best = 35
            else if (id.indexOf(q) >= 0) best = 30
            else if (c.indexOf(q) >= 0) best = 20
        }
        return best
    }

    // The visible rows for the current tab / query.
    readonly property var results: {
        var q = root.query.trim().toLowerCase()
        var list = []
        if (q !== "") {
            var all = root.allApps()
            for (var i = 0; i < all.length; i++) {
                var s = root.score(all[i], q)
                if (s >= 0) list.push({ e: all[i], s: s + Math.min(root.uses(all[i]), 20) * 0.2 })
            }
            list.sort(function (a, b) { return b.s - a.s })
            return list.map(function (x) { return x.e })
        }
        if (root.tab === 0) {
            var seen = ({}), out = []
            for (var r = 0; r < root.store.recent.length; r++) {
                var e = root.byId(root.store.recent[r])
                if (e && !seen[e.id]) { seen[e.id] = true; out.push(e) }
            }
            return out
        }
        if (root.tab === 1) {
            var p = []
            for (var k = 0; k < root.store.pinned.length; k++) {
                var pe = root.byId(root.store.pinned[k])
                if (pe) p.push(pe)
            }
            return p
        }
        var a = root.allApps()
        a.sort(function (x, y) {
            var d = root.uses(y) - root.uses(x)
            if (d !== 0) return d
            return String(x.name).toLowerCase() < String(y.name).toLowerCase() ? -1 : 1
        })
        return a
    }

    function launch(e) {
        if (!e) return
        var s = root.store
        s.counts[e.id] = (s.counts[e.id] || 0) + 1
        s.recent = [e.id].concat(s.recent.filter(function (x) { return x !== e.id })).slice(0, 12)
        root.store = s
        root.save()
        root.close()
        if (e.runInTerminal) Quickshell.execDetached(["ghostty", "-e"].concat(e.command))
        else e.execute()
    }
    function togglePin(e) {
        if (!e) return
        var s = root.store
        var i = s.pinned.indexOf(e.id)
        if (i >= 0) s.pinned.splice(i, 1); else s.pinned.push(e.id)
        root.store = s
        root.save()
        root.tab = root.tab    // re-evaluate results
        root.store = ({ counts: s.counts, recent: s.recent, pinned: s.pinned.slice() })
    }

    Loader {
        active: root.opened
        sourceComponent: PanelWindow {
            id: win
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            focusable: true
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // click outside the card closes
            MouseArea { anchors.fill: parent; onClicked: root.close() }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(640, parent.width - 40)
                height: Math.min(540, parent.height - 80)
                radius: root.theme.popupRadius
                color: root.theme.panelBackground
                border.width: 1
                border.color: root.theme.outlineVariant

                Grain {}
                MouseArea { anchors.fill: parent }   // swallow clicks inside the card

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10

                    // ---- tabs
                    Row {
                        spacing: 6
                        Repeater {
                            model: ["Recent", "Pinned", "All"]
                            delegate: Rectangle {
                                required property int index
                                required property string modelData
                                height: 30
                                width: tabLabel.implicitWidth + 24
                                radius: 15
                                color: root.tab === index && root.query === "" ? root.theme.accent : "transparent"
                                Text {
                                    id: tabLabel
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    color: root.tab === parent.index && root.query === "" ? root.theme.textOnAccent : root.theme.textMuted
                                    font.family: root.theme.fontFamily
                                    font.pixelSize: root.theme.fontSize
                                    font.bold: root.tab === parent.index && root.query === ""
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { root.tab = parent.index; root.query = ""; root.current = 0; search.forceActiveFocus() }
                                }
                            }
                        }
                    }

                    // ---- results
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
                            height: 50
                            radius: 12
                            color: root.current === row.index ? root.theme.accentSoft
                                 : (hover.hovered ? root.theme.hoverFill : "transparent")
                            border.width: root.current === row.index ? 1 : 0
                            border.color: root.theme.accent

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 12
                                Image {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    sourceSize.width: 64
                                    sourceSize.height: 64
                                    asynchronous: true
                                    source: Quickshell.iconPath(row.modelData.icon, "application-x-executable")
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    Text {
                                        Layout.fillWidth: true
                                        text: row.modelData.name
                                        color: root.theme.barText
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.fontSize + 1
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: row.modelData.comment || row.modelData.genericName || ""
                                        color: root.theme.textMuted
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.fontSize - 1
                                        elide: Text.ElideRight
                                    }
                                }
                                Text {
                                    visible: root.pinned(row.modelData)
                                    text: ""
                                    color: root.theme.accent
                                    font.family: root.theme.glyphFont
                                    font.pixelSize: 13
                                }
                            }
                            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: function (m) {
                                    if (m.button === Qt.RightButton) root.togglePin(row.modelData)
                                    else root.launch(row.modelData)
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: list.count === 0
                            text: root.query !== "" ? "No matching apps"
                                : (root.tab === 1 ? "Nothing pinned yet. Right-click an app to pin it."
                                : "Nothing here yet")
                            color: root.theme.textMuted
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSize
                        }
                    }

                    // ---- search + power
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Rectangle {
                            Layout.fillWidth: true
                            height: 42
                            radius: 21
                            color: root.theme.surfaceHigh
                            border.width: 1
                            border.color: search.activeFocus ? root.theme.accent : root.theme.outlineVariant

                            Text {
                                id: lens
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                text: ""
                                color: root.theme.textMuted
                                font.family: root.theme.glyphFont
                                font.pixelSize: 14
                            }
                            TextInput {
                                id: search
                                anchors.left: lens.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.theme.barText
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fontSize + 1
                                selectByMouse: true
                                clip: true
                                focus: true
                                text: root.query
                                onTextChanged: { root.query = text; root.current = 0 }
                                Component.onCompleted: forceActiveFocus()

                                Keys.onPressed: function (ev) {
                                    var n = list.count
                                    if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true }
                                    else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Tab) { if (n) root.current = (root.current + 1) % n; ev.accepted = true }
                                    else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab) { if (n) root.current = (root.current - 1 + n) % n; ev.accepted = true }
                                    else if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && n) { root.launch(root.results[root.current]); ev.accepted = true }
                                    else if (ev.key === Qt.Key_P && (ev.modifiers & Qt.ControlModifier) && n) { root.togglePin(root.results[root.current]); ev.accepted = true }
                                    else if (search.text === "" && ev.key === Qt.Key_Left) { root.tab = (root.tab + 2) % 3; root.current = 0; ev.accepted = true }
                                    else if (search.text === "" && ev.key === Qt.Key_Right) { root.tab = (root.tab + 1) % 3; root.current = 0; ev.accepted = true }
                                }
                            }
                            Text {
                                anchors.left: lens.right
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                visible: search.text === ""
                                text: "Search applications…"
                                color: root.theme.textMuted
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fontSize + 1
                            }
                        }
                        Rectangle {
                            width: 42; height: 42; radius: 21
                            color: powerHover.hovered ? root.theme.hoverFill : root.theme.surfaceHigh
                            border.width: 1
                            border.color: root.theme.outlineVariant
                            Text {
                                anchors.centerIn: parent
                                text: ""
                                color: root.theme.barText
                                font.family: root.theme.glyphFont
                                font.pixelSize: 15
                            }
                            HoverHandler { id: powerHover; cursorShape: Qt.PointingHandCursor }
                            MouseArea { anchors.fill: parent; onClicked: { root.close(); root.powerAction() } }
                        }
                    }
                }
            }
        }
    }
}
