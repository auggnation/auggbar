import QtQuick

// Display — monitor icon + live brightness %. Click for the displays &
// brightness panel, scroll to change brightness.
BarButton {
    id: w
    required property var shell
    property bool shown: true
    readonly property var settingsSchema: [
        { key: "showPercent", label: "Show brightness %", type: "bool", default: true }
    ]

    // NB: keep escapes to 4 hex digits. \uXXXX consumes exactly 4, so a
    // 5-digit Nerd Font code such as "9" silently becomes U+F037
    // followed by "9" and renders as a junk glyph plus a stray character.
    glyph: ""           // Font Awesome monitor outline
    glyphSize: 16
    label: shell.barOpt("display", "showPercent", true) ? shell.brightness + "%" : ""
    highlight: shell.displayOpen
    onClicked: {
        w.shell.displayOpen = !w.shell.displayOpen
        w.shell.sbOpen = false
        w.shell.sbSetOpen = false
        if (w.shell.displayOpen) { w.shell.refreshDisplay(); w.shell.readBrightness(); w.shell.auggRead() }
    }
    onScrolled: function (d) { w.shell.setBrightness(d > 0 ? "5%+" : "5%-") }
}
