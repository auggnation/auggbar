import QtQuick

// Updater — CachyOS update indicator, only present while updates are
// pending. Click opens the updater, right-click re-checks.
UpdateButton {
    required property var shell
    property bool shown: true
    pending: shell.updatesPending
    busy: shell.updatesChecking
    iconPath: shell.updateIconPath
    count: shell.updateCount
    onClicked: shell.run("ghostty --title=arch-update -e arch-update")
    onRightClicked: shell.forceUpdateCheck()
}
