pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: barConfig

    // Bar dimensions and appearance
    property int height: 28
    property int padding: 12
    property int spacing: 6
    property int radius: 12
    property bool showBackground: true
    property string position: "top" // top, bottom

    // Widget visibility
    property var widgetStates: ({})

    function getWidgetVisible(name) {
        if (widgetStates[name] === undefined) return true
        return widgetStates[name]
    }

    function setWidgetVisible(name, visible) {
        widgetStates[name] = visible
    }
}
