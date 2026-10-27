import QtQuick
import Quickshell

// Palette + metrics, read from the live Auggment theme (colors.toml / shell.toml)
// so the bar matches the rest of the desktop. Defaults are a dark Tokyo Night
// fallback for the brief moment before the files are read.
QtObject {
    id: t

    property color foreground: "#a9b1d6"
    property color background: "#1a1b26"
    property color accent: "#7aa2f7"
    property color urgent: "#f7768e"
    property color muted: "#565f89"

    property color barBackground: "#1a1b26"
    property color barText: "#a9b1d6"
    property color barActive: "#f7768e"

    property int barHeight: 26
    property int radius: 10
    property int pad: 12
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 12

    property string themeDir: Quickshell.env("HOME") + "/.local/state/auggment/theme"

    readonly property color hoverFill: Qt.rgba(t.barText.r, t.barText.g, t.barText.b, 0.08)
    readonly property color normalFill: Qt.rgba(t.barText.r, t.barText.g, t.barText.b, 0.05)
    readonly property color cardFill: Qt.rgba(t.foreground.r, t.foreground.g, t.foreground.b, 0.04)
    readonly property color cardBorder: Qt.rgba(t.foreground.r, t.foreground.g, t.foreground.b, 0.16)
    readonly property color popupBorder: t.accent
    property int popupRadius: 14
    readonly property color textMuted: Qt.rgba(t.barText.r, t.barText.g, t.barText.b, 0.6)
    readonly property color accentSoft: Qt.rgba(t.accent.r, t.accent.g, t.accent.b, 0.16)

    function keyVal(line) {
        var m = String(line).match(/^\s*([A-Za-z0-9_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s#]+))/)
        if (!m) return null
        var v = (m[2] !== undefined) ? m[2] : (m[3] !== undefined ? m[3] : m[4])
        return { k: m[1], v: v }
    }

    function applyColors(raw) {
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var kv = keyVal(lines[i])
            if (!kv) continue
            if (kv.k === "foreground") t.foreground = kv.v
            else if (kv.k === "background") t.background = kv.v
            else if (kv.k === "accent") t.accent = kv.v
            else if (kv.k === "muted") t.muted = kv.v
            else if (kv.k === "red" || kv.k === "color1") t.urgent = kv.v
        }
    }

    function applyShell(raw) {
        var lines = String(raw || "").split("\n")
        var section = ""
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            var sm = line.match(/^\s*\[([A-Za-z0-9_-]+)\]/)
            if (sm) { section = sm[1]; continue }
            var kv = keyVal(line)
            if (!kv) continue
            if (section === "bar") {
                if (kv.k === "background") t.barBackground = kv.v
                else if (kv.k === "text") t.barText = kv.v
                else if (kv.k === "active") t.barActive = kv.v
                else if (kv.k === "size-horizontal") t.barHeight = parseInt(kv.v) || t.barHeight
            }
        }
    }

    // Wallpaper-derived overrides written by auggment-wallpaper-rotate. These
    // win over the static theme so the bar follows the current background.
    function applyPalette(raw) {
        var lines = String(raw || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var kv = keyVal(lines[i])
            if (!kv) continue
            if (kv.k === "accent") t.accent = kv.v
            else if (kv.k === "background") { t.background = kv.v; t.barBackground = kv.v }
            else if (kv.k === "foreground") { t.foreground = kv.v; t.barText = kv.v }
            else if (kv.k === "muted") t.muted = kv.v
            else if (kv.k === "urgent") t.urgent = kv.v
        }
    }

    // One payload: colors.toml, =====PALETTE=====, palette.toml,
    // =====SHELL=====, shell.toml. Applied in that order so the palette wins.
    function applyTheme(raw) {
        var parts = String(raw || "").split("=====PALETTE=====")
        applyColors(parts[0])
        var rest = parts.length > 1 ? parts[1] : ""
        var sp = rest.split("=====SHELL=====")
        applyPalette(sp[0])
        applyShell(sp.length > 1 ? sp[1] : "")
    }
}
