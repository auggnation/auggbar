import QtQuick
import "../components"

// Viking — the running-viking system monitor.
Item {
    id: w
    required property var shell
    property bool shown: true
    function openSettings() { viking.settingsOpen = !viking.settingsOpen }
    implicitWidth: viking.implicitWidth
    implicitHeight: viking.implicitHeight
    RunViking { id: viking; hostTheme: w.shell.theme }
}
