pragma Singleton
import QtQuick
import Quickshell

// Palette + metrics, read from the live Auggment theme (colors.toml / shell.toml)
// so the bar matches the rest of the desktop. Defaults are a dark Tokyo Night
// fallback for the brief moment before the files are read.
Singleton {
    id: t

    property color foreground: "#a9b1d6"
    property color background: "#1a1b26"
    property color accent: "#7aa2f7"
    property color urgent: "#f7768e"
    property color muted: "#565f89"
    // Extra wallpaper-derived shades (colors.toml), used by the visualizer.
    property color brightForeground: "#c0caf5"
    property color darkerBackground: "#16161e"
    property color lighterBackground: "#24283b"

    // Noctalia-style surfaces (rendered from the wallpaper palette by the
    // auggbar-palette template): panels sit on surface_container, controls on
    // surface_container_high, edges are the soft outline_variant.
    property color panelBackground: "#1f2030"
    property color surfaceHigh: "#24283b"
    property color surfaceHighest: "#2f334d"
    property color outlineVariant: "#3b3f5c"
    property color textOnAccent: "#1a1b26"

    property color barBackground: "#1a1b26"
    property color barText: "#a9b1d6"
    property color barActive: "#f7768e"

    property int barHeight: 34
    property int radius: 12
    property int pad: 12
    // Text uses the desktop sans (the same face Noctalia uses); the Nerd Font
    // stays available as the glyph face and as the fallback for icon codepoints.
    property string fontFamily: "Noto Sans"
    property string glyphFont: "JetBrainsMono Nerd Font"
    property int fontSize: 12

    property string themeDir: Quickshell.env("HOME") + "/.local/state/auggment/theme"

    readonly property color hoverFill: Qt.rgba(t.barText.r, t.barText.g, t.barText.b, 0.08)
    readonly property color normalFill: t.surfaceHigh
    readonly property color cardFill: t.surfaceHigh
    readonly property color cardBorder: t.outlineVariant
    readonly property color popupBorder: t.outlineVariant
    property int popupRadius: 16
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
            else if (kv.k === "bright_foreground") t.brightForeground = kv.v
            else if (kv.k === "darker_background") t.darkerBackground = kv.v
            else if (kv.k === "lighter_background") t.lighterBackground = kv.v
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
            else if (kv.k === "panel") t.panelBackground = kv.v
            else if (kv.k === "surface_high") t.surfaceHigh = kv.v
            else if (kv.k === "surface_highest") t.surfaceHighest = kv.v
            else if (kv.k === "outline") t.outlineVariant = kv.v
            else if (kv.k === "on_accent") t.textOnAccent = kv.v
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
