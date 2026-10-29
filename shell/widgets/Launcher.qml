import QtQuick
import "../components"

// Menu button — opens the desktop launcher (hyprlauncher). The plugin also
// owns the Super+Space shortcut, so the button and the key always agree.
Item {
    id: w
    required property var shell
    property bool shown: true
    function openSettings() { btn.settingsOpen = !btn.settingsOpen }
    implicitWidth: btn.implicitWidth
    implicitHeight: btn.implicitHeight

    LauncherButton {
        id: btn
        hostTheme: w.shell.theme
        Component.onCompleted: w.shell.launcherPlugin = btn
    }
}
