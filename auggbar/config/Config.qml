import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: config

    property string configDir: Quickshell.env("HOME") + "/.config/auggbar"
    property string settingsPath: configDir + "/settings.json"

    // Bar settings
    property string barPosition: "top"
    property int barHeight: 28
    property bool barBackground: true
    property int barCornerRadius: 12
    property int barPadding: 12
    property int barSpacing: 6

    // Widget settings
    property var widgets: [
        {"id": "launcher", "enabled": true, "order": 0, "label": "Launcher"},
        {"id": "workspaces", "enabled": true, "order": 1, "label": "Workspaces"},
        {"id": "weather", "enabled": true, "order": 10, "label": "Weather"},
        {"id": "calendar", "enabled": true, "order": 11, "label": "Calendar"},
        {"id": "nowplaying", "enabled": true, "order": 12, "label": "Now Playing"},
        {"id": "netspeed", "enabled": true, "order": 20, "label": "Network Speed"},
        {"id": "audio", "enabled": true, "order": 21, "label": "Audio"},
        {"id": "mic", "enabled": true, "order": 22, "label": "Microphone"},
        {"id": "bluetooth", "enabled": true, "order": 23, "label": "Bluetooth"},
        {"id": "scoreboard", "enabled": true, "order": 30, "label": "Scoreboard"},
        {"id": "display", "enabled": true, "order": 31, "label": "Display"},
        {"id": "updater", "enabled": true, "order": 40, "label": "Updater"},
        {"id": "clock", "enabled": true, "order": 50, "label": "Clock"}
    ]

    function load() {
        // Load from settings.json
    }

    function save() {
        // Save to settings.json
    }

    function getWidget(id) {
        for (var i = 0; i < widgets.length; i++) {
            if (widgets[i].id === id) return widgets[i]
        }
        return null
    }

    function isWidgetEnabled(id) {
        var w = getWidget(id)
        return w ? w.enabled : false
    }

    function setWidgetEnabled(id, enabled) {
        for (var i = 0; i < widgets.length; i++) {
            if (widgets[i].id === id) {
                widgets[i].enabled = enabled
                widgets = widgets.slice()
                break
            }
        }
        save()
    }
}
