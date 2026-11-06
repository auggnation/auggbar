import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import ".."

// Notifications — the desktop notification daemon, built into the shell.
// Owns org.freedesktop.Notifications (so only one daemon may run), shows up to
// five popups at the top right under the bar, honours expire timeouts, keeps
// critical ones until dismissed. Click a popup to dismiss it; action buttons
// invoke the app's actions. Do-not-disturb: `qs ipc call notifications dnd`.
Item {
    id: root
    readonly property QtObject theme: Theme

    property var entries: []          // [{ n: Notification, deadline: ms (0 = sticky) }]
    property bool doNotDisturb: false

    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: function (n) {
            n.tracked = true
            if (root.doNotDisturb && n.urgency !== NotificationUrgency.Critical) return
            root.add(n)
        }
    }

    function add(n) {
        var sticky = n.urgency === NotificationUrgency.Critical
        var secs = n.expireTimeout > 0 ? n.expireTimeout : 6
        var e = { n: n, deadline: sticky ? 0 : Date.now() + secs * 1000 }
        var next = [e].concat(root.entries.filter(function (x) { return x.n !== n })).slice(0, 5)
        root.entries = next
        sweep.running = true
    }
    function remove(n) {
        root.entries = root.entries.filter(function (x) { return x.n !== n })
    }
    function dismiss(n) {
        root.remove(n)
        n.dismiss()
    }

    Timer {
        id: sweep
        interval: 500
        repeat: true
        running: false
        onTriggered: {
            var now = Date.now()
            var keep = root.entries.filter(function (x) { return x.deadline === 0 || x.deadline > now })
            if (keep.length !== root.entries.length) root.entries = keep
            if (keep.length === 0) running = false
        }
    }

    IpcHandler {
        target: "notifications"
        function dnd(): void { root.doNotDisturb = !root.doNotDisturb }
        function clear(): void {
            var all = root.entries.slice()
            root.entries = []
            for (var i = 0; i < all.length; i++) all[i].n.dismiss()
        }
    }

    PanelWindow {
        visible: root.entries.length > 0
        anchors { top: true; right: true }
        margins { top: root.theme.barHeight + 14; right: 12 }
        implicitWidth: 360
        implicitHeight: stack.implicitHeight
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "auggbar-notifications"

        Column {
            id: stack
            width: parent.width
            spacing: 8

            Repeater {
                model: root.entries
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property var n: modelData.n
                    width: stack.width
                    height: body.implicitHeight + 24
                    radius: root.theme.popupRadius
                    color: root.theme.panelBackground
                    border.width: 1
                    border.color: root.theme.outlineVariant

                    Grain {}
                    // urgency edge
                    Rectangle {
                        width: 3
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 1 }
                        color: card.n.urgency === NotificationUrgency.Critical ? root.theme.urgent : root.theme.accent
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.dismiss(card.n)
                    }

                    ColumnLayout {
                        id: body
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12; leftMargin: 16 }
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Image {
                                visible: source !== ""
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                sourceSize.width: 36
                                sourceSize.height: 36
                                source: card.n.appIcon ? Quickshell.iconPath(card.n.appIcon, true) : ""
                            }
                            Text {
                                Layout.fillWidth: true
                                text: card.n.appName
                                color: root.theme.textMuted
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fontSize - 2
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.n.summary
                            color: root.theme.barText
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSize + 1
                            font.bold: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.n.body
                            textFormat: Text.StyledText
                            color: root.theme.barText
                            opacity: 0.85
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fontSize
                            wrapMode: Text.WordWrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                        }
                        Row {
                            visible: card.n.actions.length > 0
                            spacing: 6
                            Repeater {
                                model: card.n.actions
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 26
                                    width: actLabel.implicitWidth + 20
                                    radius: 6
                                    color: root.theme.surfaceHigh
                                    border.width: 1
                                    border.color: root.theme.outlineVariant
                                    Text {
                                        id: actLabel
                                        anchors.centerIn: parent
                                        text: parent.modelData.text
                                        color: root.theme.barText
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.fontSize - 1
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { parent.modelData.invoke(); root.remove(card.n) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
