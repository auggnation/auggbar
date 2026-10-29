import QtQuick

// Mic — microphone state; click to mute/unmute.
BarButton {
    required property var shell
    property bool shown: true
    glyph: shell.micGlyph(); glyphSize: 15
    glyphColor: shell.micOn() ? theme.barText : theme.urgent
    onClicked: { shell.run("'" + shell.home + "/.local/bin/auggment-mic' toggle"); shell.volRefreshSoon(); shell.micProbeSoon() }
}
