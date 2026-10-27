import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Hyprland
import "./Theme.qml"
import "./config/Config.qml"
import "./config/BarConfig.qml"
import "./modules/ToggleMenu.qml"
import "./components/LauncherButton.qml"

Scope {
    id: root

    property string home: Quickshell.env("HOME")

    Config {
        id: cfg
    }

    BarConfig {
        id: barcfg
    }

    ToggleMenu {
        id: toggleMenu
        configRef: cfg
    }

    PanelWindow {
        id: bar

        anchors {
            top: barcfg.position === "top"
            bottom: barcfg.position === "bottom"
            left: true
            right: true
        }

        height: barcfg.height
        color: "transparent"

        margins {
            left: barcfg.padding
            right: barcfg.padding
            top: barcfg.position === "top" ? 4 : 0
            bottom: barcfg.position === "bottom" ? 4 : 0
        }

        WlrLayershell.namespace: "quickshell:auggbar"

        Rectangle {
            id: barBg
            anchors.fill: parent
            color: Theme.barBackground
            radius: barcfg.radius
            opacity: 0.92
            visible: barcfg.showBackground
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    toggleMenu.toggle()
                } else if (mouse.button === Qt.LeftButton && mouse.modifiers & Qt.AltModifier) {
                    toggleMenu.toggle()
                }
            }
        }

        RowLayout {
            id: leftSection
            anchors.left: parent.left
            anchors.leftMargin: barcfg.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: barcfg.spacing

            LauncherButton {
                visible: barcfg.getWidgetVisible("launcher")
            }
        }

        RowLayout {
            id: centerSection
            anchors.centerIn: parent
            spacing: barcfg.spacing
        }

        RowLayout {
            id: rightSection
            anchors.right: parent.right
            anchors.rightMargin: barcfg.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: barcfg.spacing

            // Plugins and widgets will be added here
            Text {
                text: "auggbar"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                visible: barcfg.getWidgetVisible("clock")
            }
        }
    }

    IpcHandler {
        target: "auggbar"

        function toggleMenu() {
            toggleMenu.toggle()
        }

        function toggleWidget(name: string) {
            barcfg.setWidgetVisible(name, !barcfg.getWidgetVisible(name))
        }

        function reload() {
            Quickshell.reloadConfig()
        }
    }
}
