import QtQuick

// PluginSlot — hosts one bar plugin.
//
// Loads widgets/<File>.qml for `pluginId` and lays a click-catcher over it:
// right-click or Alt+click opens that plugin's settings (its own panel when
// the plugin has `openSettings()`, otherwise the generic plugin settings
// popup). Every other press, and the wheel, passes straight through to the
// plugin underneath.
Item {
    id: slot
    required property var shell
    required property string pluginId
    // Containers (the system card) host slots of their own, so they must not
    // swallow right-clicks meant for their children.
    property bool catchClicks: true

    readonly property var item: ld.item
    readonly property bool shown: ld.status === Loader.Ready && ld.item.shown !== false
    visible: shown
    implicitWidth: ld.implicitWidth
    implicitHeight: ld.implicitHeight

    Loader {
        id: ld
        Component.onCompleted: setSource(slot.shell.barWidgetUrl(slot.pluginId), { shell: slot.shell })
        onLoaded: slot.shell.barItems[slot.pluginId] = item
    }

    MouseArea {
        anchors.fill: parent
        z: 100
        enabled: slot.catchClicks
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function (m) {
            if (m.button === Qt.RightButton || (m.modifiers & Qt.AltModifier)) {
                const p = slot.mapToItem(null, 0, 0)
                slot.shell.openPluginSettings(slot.pluginId, p.x)
            } else {
                m.accepted = false
            }
        }
    }
}
