import QtQuick

// Grain — a film-grain / scuffed-metal overlay for panels and the bar. Sits
// just inside the border, under the content. Turn the texture down with
// `strength` (0 disables it).
Item {
    property real strength: 0.12
    anchors.fill: parent
    anchors.margins: 1
    visible: strength > 0
    opacity: strength
    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../assets/grain.png")
        fillMode: Image.Tile
        smooth: false
        cache: true
    }
}
