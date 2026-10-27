import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../Theme.qml"

PanelWindow {
    id: toggleMenu

    property var configRef: null

    visible: false
    width: 320
    height: 420
    color: "transparent"

    anchors {
        top: true
    }

    margins {
        top: Theme.barHeight + 8
        left: 8
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.barBackground
        radius: Theme.radius
        border.color: Theme.muted
        border.width: 1
        opacity: 0.98
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        Text {
            text: "Auggbar Settings"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
            Layout.fillWidth: true
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.muted
            opacity: 0.3
        }

        Text {
            text: "Widgets"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
            Layout.fillWidth: true
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: widgetColumn.height
            clip: true

            ColumnLayout {
                id: widgetColumn
                width: parent.width
                spacing: 4

                Repeater {
                    model: ["launcher", "workspaces", "weather", "calendar", "nowplaying",
                            "netspeed", "audio", "mic", "bluetooth", "scoreboard",
                            "display", "updater", "clock"]

                    Rectangle {
                        Layout.fillWidth: true
                        height: 28
                        color: mouseArea.containsMouse ? Theme.hoverFill : "transparent"
                        radius: 6

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                                text: modelData
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                Layout.fillWidth: true
                                capitalization: Font.Capitalize
                            }

                            Rectangle {
                                width: 40
                                height: 20
                                radius: 10
                                color: toggle.checked ? Theme.accent : Theme.muted

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    x: toggle.checked ? 22 : 2
                                    y: 2
                                    color: Theme.foreground
                                }

                                MouseArea {
                                    id: toggle
                                    anchors.fill: parent
                                    property bool checked: true
                                    onClicked: checked = !checked
                                }
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }
                }
            }
        }
    }

    function toggle() {
        visible = !visible
    }

    function show() { visible = true }
    function hide() { visible = false }
}
