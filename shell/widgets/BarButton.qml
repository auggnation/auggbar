import QtQuick
import ".."

// BarButton — compact glyph/label button used by the bar widgets.
Rectangle {
    id: b
    readonly property QtObject theme: Theme
    property string glyph: ""
    property string label: ""
    property color fg: theme.barText
    property color glyphColor: b.fg
    property int glyphSize: 15
    property bool highlight: false
    property color bgColor: "transparent"
    property color borderColor: "transparent"
    property int hPad: 8
    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal scrolled(int dir)

    implicitWidth: row.implicitWidth + b.hPad * 2
    implicitHeight: theme.barHeight - 8
    radius: theme.radius
    color: (hover.hovered || b.highlight) ? theme.hoverFill : b.bgColor
    border.width: b.borderColor.a > 0.001 ? 1 : 0
    border.color: b.borderColor
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Text {
            visible: b.glyph !== ""
            text: b.glyph
            color: b.glyphColor
            font.family: theme.fontFamily
            font.pixelSize: b.glyphSize
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: b.label !== ""
            text: b.label
            color: b.fg
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: function (m) {
            if (m.button === Qt.RightButton) b.rightClicked()
            else if (m.button === Qt.LeftButton) b.clicked()
            else if (m.button === Qt.MiddleButton) b.middleClicked()
        }
        onWheel: function (w) { b.scrolled(w.angleDelta.y > 0 ? 1 : -1) }
    }
}
