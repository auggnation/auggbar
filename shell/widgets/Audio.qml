import QtQuick

// Audio — output volume. Click for the sound panel, middle-click to mute,
// scroll to change volume.
BarButton {
    tone: 2
    required property var shell
    property bool shown: true
    readonly property var settingsSchema: [
        { key: "step", label: "Scroll step", type: "number", default: 5, min: 1, max: 10, step: 1, suffix: "%" }
    ]
    readonly property int step: shell.barOpt("audio", "step", 5)
    glyph: shell.volGlyph(); glyphSize: 15
    highlight: shell.sndOpen
    onClicked: shell.openSnd()
    onMiddleClicked: { shell.run("auggment-vol mute"); shell.volRefreshSoon() }
    onScrolled: function (d) { shell.run("auggment-vol " + (d > 0 ? "up " : "down ") + step); shell.volRefreshSoon() }
}
