import QtQuick
import ".."

// SystemGroup — one card holding every widget whose settings.json section
// is "system" (net speed, network, audio, mic, bluetooth, battery, ...).
Rectangle {
    id: w
    required property var shell
    readonly property QtObject theme: Theme
    readonly property var items: shell.barSection("system")
    property bool shown: items.length > 0

    implicitWidth: row.implicitWidth + 8
    implicitHeight: theme.barHeight - 6
    radius: 9
    color: theme.cardFill
    border.width: 1
    border.color: theme.cardBorder

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0
        Repeater {
            model: w.items
            delegate: PluginSlot {
                required property var modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                shell: w.shell
                pluginId: modelData.id
                width: visible ? implicitWidth : 0
            }
        }
    }
}
