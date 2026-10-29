import QtQuick

// Audio — output volume. Click for the sound panel, middle-click to mute,
// scroll to change volume.
BarButton {
    required property var shell
    property bool shown: true
    readonly property var settingsSchema: [
        { key: "step", label: "Scroll step", type: "number", default: 5, min: 1, max: 10, step: 1, suffix: "%" }
    ]
    readonly property int step: shell.barOpt("audio", "step", 5)
    glyph: shell.volGlyph(); glyphSize: 15
    highlight: shell.sndOpen
    onClicked: shell.openSnd()
    onMiddleClicked: { shell.run("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"); shell.volRefreshSoon() }
    onScrolled: function (d) { shell.run("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + (d > 0 ? step + "%+" : step + "%-")); shell.volRefreshSoon() }
}
