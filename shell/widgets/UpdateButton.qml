import QtQuick
import ".."

// UpdateButton — CachyOS update indicator; collapses to zero width when idle.
Rectangle {
    id: ub
    readonly property QtObject theme: Theme
    property bool pending: false
    property bool busy: false
    property string iconPath: ""
    property int count: 0
    signal clicked()
    signal rightClicked()

    // The button itself always stays rendered. An image whose source
    // changes while it is hidden never finishes loading, so the icon
    // would not reappear on the next update. It is hidden by dropping the
    // source and collapsing the width instead.
    visible: true
    implicitWidth: ub.pending ? ubRow.implicitWidth + 10 : 0
    implicitHeight: theme.barHeight - 8
    radius: theme.radius
    color: ub.busy ? theme.accentSoft : (hover.hovered ? theme.hoverFill : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: ubRow
        anchors.centerIn: parent
        spacing: 4
        // The icon is wrapped so the row reserves 16px for it: an Image
        // would report the SVG's natural 200px as its implicit width.
        Item {
            width: 16
            height: 16
            implicitWidth: 16
            implicitHeight: 16
            Image {
                anchors.fill: parent
                source: ub.pending ? ub.iconPath : ""
                asynchronous: false
                fillMode: Image.PreserveAspectFit
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: ub.pending && ub.count > 0
            text: ub.count
            color: theme.barText
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
            font.bold: true
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function (m) {
            if (m.button === Qt.RightButton) ub.rightClicked()
            else ub.clicked()
        }
    }
}
