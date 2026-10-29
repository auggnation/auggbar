import QtQuick

// Network — wifi/ethernet glyph; click for the network panel.
BarButton {
    required property var shell
    property bool shown: true
    glyph: shell.netGlyph(); glyphSize: 15
    highlight: shell.netOpen
    onClicked: shell.openNet()
    onRightClicked: shell.openNet()
}
