import QtQuick
import Quickshell.Hyprland
import ".."

// WindowTitle — title of the focused window.
Text {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    property bool shown: text !== ""
    readonly property var settingsSchema: [
        { key: "maxWidth", label: "Max width", type: "number", default: 420, min: 100, max: 800, step: 20, suffix: " px" }
    ]
    width: Math.min(implicitWidth, shell.barOpt("title", "maxWidth", 420))
    elide: Text.ElideRight
    text: Hyprland.activeToplevel ? (Hyprland.activeToplevel.title || "") : ""
    color: theme.textMuted
    font.family: theme.fontFamily
    font.pixelSize: theme.fontSize
}
