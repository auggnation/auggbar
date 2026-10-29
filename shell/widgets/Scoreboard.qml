import QtQuick
import ".."

// Scoreboard: favourite teams only.
// Not live -> "AWAY @ HOME"; live -> "AWAY 12:7 HOME". Click for the board,
// right-click for settings, scroll to step through games.
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: true
    function openSettings() { w.shell.openSbSet() }

    readonly property var cur: shell.sbCurrent()
    readonly property bool isGame: !!w.cur && w.cur.kind === "game"
    readonly property bool showScore: shell.sbStarted(w.cur)
    readonly property bool withLogos: w.isGame && shell.sbShowBarLogos()
    readonly property color tone: shell.sbColor(w.cur)

    implicitHeight: theme.barHeight - 8
    implicitWidth: row.implicitWidth + 18
    radius: theme.radius
    color: (hover.hovered || shell.sbOpen) ? theme.hoverFill : Qt.rgba(w.tone.r, w.tone.g, w.tone.b, 0.14)
    border.width: 1
    border.color: Qt.rgba(w.tone.r, w.tone.g, w.tone.b, 0.45)
    Behavior on color { ColorAnimation { duration: 120 } }

    function side(s) { return (w.cur && w.cur[s]) ? w.cur[s] : null }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Image {
            visible: w.withLogos
            width: 15; height: 15
            anchors.verticalCenter: parent.verticalCenter
            source: (w.side("away") && w.side("away").logo) ? w.side("away").logo : ""
            sourceSize.width: 30
            sourceSize.height: 30
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
        }
        Text {
            visible: w.isGame
            anchors.verticalCenter: parent.verticalCenter
            text: (w.side("away") && w.side("away").abbr) ? w.side("away").abbr : "?"
            color: w.shell.sbTeamColor(w.shell.sbTeamKey(w.cur, "away"), w.side("away") ? w.side("away").color : w.theme.barText)
            font.family: w.theme.fontFamily
            font.pixelSize: w.theme.fontSize
            font.bold: true
        }
        Text {
            visible: w.isGame
            anchors.verticalCenter: parent.verticalCenter
            text: {
                if (!w.cur) return ""
                if (!w.showScore) return "@"
                var a = w.cur.away || {}, h = w.cur.home || {}
                var av = (a.score !== undefined && a.score !== null) ? a.score : 0
                var hv = (h.score !== undefined && h.score !== null) ? h.score : 0
                return av + ":" + hv
            }
            color: w.tone
            font.family: w.theme.fontFamily
            font.pixelSize: w.theme.fontSize
            font.bold: true
        }
        Text {
            visible: w.isGame
            anchors.verticalCenter: parent.verticalCenter
            text: (w.side("home") && w.side("home").abbr) ? w.side("home").abbr : "?"
            color: w.shell.sbTeamColor(w.shell.sbTeamKey(w.cur, "home"), w.side("home") ? w.side("home").color : w.theme.barText)
            font.family: w.theme.fontFamily
            font.pixelSize: w.theme.fontSize
            font.bold: true
        }
        Image {
            visible: w.withLogos
            width: 15; height: 15
            anchors.verticalCenter: parent.verticalCenter
            source: (w.side("home") && w.side("home").logo) ? w.side("home").logo : ""
            sourceSize.width: 30
            sourceSize.height: 30
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
        }
        Text {
            visible: !w.isGame
            anchors.verticalCenter: parent.verticalCenter
            text: w.cur ? w.shell.sbLabel(w.cur) : "Pick teams"
            color: w.tone
            font.family: w.theme.fontFamily
            font.pixelSize: w.theme.fontSize
            font.bold: true
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (m) {
            if (m.button === Qt.RightButton) { w.shell.openSbSet(); return }
            w.shell.sbOpen = !w.shell.sbOpen
            w.shell.displayOpen = false
            if (w.shell.sbOpen) { w.shell.refreshDisplay(); w.shell.afterSbWrite() }
        }
        onWheel: function (e) { w.shell.sbStep(e.angleDelta.y > 0 ? -1 : 1) }
    }
}
