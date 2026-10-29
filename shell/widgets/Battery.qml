import QtQuick

// Battery — charge glyph + percentage.
BarButton {
    required property var shell
    property bool shown: true
    readonly property var settingsSchema: [
        { key: "showPercent", label: "Show percentage", type: "bool", default: true }
    ]
    glyph: shell.batGlyph()
    label: (shell.batPct >= 0 && shell.barOpt("battery", "showPercent", true)) ? (shell.batPct + "%") : ""
    glyphSize: 15
}
