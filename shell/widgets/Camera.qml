import QtQuick
import Quickshell.Io

// Camera — a "camera in use" light. Red and struck through (like the mic's
// off state) unless an app is using the camera; while one is, it shows in the
// accent colour. If the privacy switch is off during use it stays red, since
// the app gets no picture. State comes from /run/auggment/privacy.json
// (auggment-privacy-switches.service: cam_in_use + the webcam's privacy switch).
BarButton {
    id: w
    required property var shell
    readonly property var settingsSchema: [
        { key: "onlyWhenInUse", label: "Only show while in use", type: "bool", default: false }
    ]
    property bool inUse: false
    property var camOn: null          // privacy switch: true / false / null (unknown)
    readonly property bool live: inUse && camOn !== false
    property bool shown: inUse || !shell.barOpt("camera", "onlyWhenInUse", false)

    glyph: ""                   // Font Awesome video camera
    glyphSize: 14
    glyphColor: live ? theme.accent : theme.urgent

    // Struck through whenever the camera is not live.
    Rectangle {
        visible: !w.live
        anchors.centerIn: parent
        width: 18; height: 2
        rotation: -35
        color: w.theme.urgent
    }

    FileView {
        path: "/run/auggment/privacy.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text())
                w.inUse = s.cam_in_use === true
                w.camOn = (s.cam_on === true || s.cam_on === false) ? s.cam_on : null
            } catch (e) { w.inUse = false; w.camOn = null }
        }
        onLoadFailed: { w.inUse = false; w.camOn = null }
    }
}
