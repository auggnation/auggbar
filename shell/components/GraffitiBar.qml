import QtQuick
import QtQuick.Effects
import ".."

// GraffitiBar — the bar's backdrop. Instead of a clean rounded pill it is a
// spray-painted strip: torn, speckled top and bottom edges, dry-brush fade at
// both ends and a slightly misregistered darker copy behind it. Two pieces of
// masking tape hold it up and a few frayed threads run off the right one. All
// of it is a white-on-transparent mask tinted with the wallpaper palette, so
// it recolours with the background. Textures: ../assets (make-bar-textures.py).
Item {
    id: root
    readonly property QtObject theme: Theme
    readonly property int capWidth: 96

    // a tinted copy of the strip (cap + tiled centre + mirrored cap)
    component Strip: Item {
        id: strip
        property color tint: "white"
        anchors.fill: parent
        // MultiEffect blends the white mask toward the colour by the colour's
        // alpha (washed-out grey); so tint with an opaque colour and fade the
        // whole strip instead.
        opacity: strip.tint.a

        Item {
            id: mask
            anchors.fill: parent
            visible: false
            Image {
                x: 0; width: root.capWidth; height: parent.height
                source: Qt.resolvedUrl("../assets/bar-cap.png")
                smooth: false
            }
            Image {
                x: root.capWidth
                width: Math.max(0, parent.width - 2 * root.capWidth)
                height: parent.height
                source: Qt.resolvedUrl("../assets/bar-center.png")
                fillMode: Image.TileHorizontally
                smooth: false
            }
            Image {
                x: parent.width - root.capWidth; width: root.capWidth; height: parent.height
                source: Qt.resolvedUrl("../assets/bar-cap.png")
                mirror: true
                smooth: false
            }
        }
        MultiEffect {
            anchors.fill: mask
            source: mask
            colorization: 1.0
            colorizationColor: Qt.rgba(strip.tint.r, strip.tint.g, strip.tint.b, 1)
        }
    }

    // misregistered "ghost" print, offset down-left
    Strip {
        x: -1.5; y: 1.5
        tint: Qt.rgba(root.theme.barTint.r, root.theme.barTint.g, root.theme.barTint.b, 0.35 * root.theme.barOpacity)
    }
    // the paint itself
    Strip {
        tint: Qt.rgba(root.theme.barTint.r, root.theme.barTint.g, root.theme.barTint.b, root.theme.barOpacity)
    }

    // a second, faint pass of grain so the fill is not flat
    Grain { strength: 0.10; anchors.margins: 6 }

    // ---------------------------------------------------------------- tape
    component Tape: Item {
        id: tp
        property string src: "tape-a.png"
        property real tilt: 0
        width: img.sourceSize.width; height: img.sourceSize.height
        rotation: tp.tilt
        Image { id: img; source: Qt.resolvedUrl("../assets/" + tp.src); visible: false; smooth: false }
        // soft shadow under the tape
        MultiEffect {
            x: 1; y: 2
            width: img.width; height: img.height
            source: img
            colorization: 1.0
            colorizationColor: "black"
            opacity: 0.35
        }
        MultiEffect {
            width: img.width; height: img.height
            source: img
            colorization: 1.0
            colorizationColor: Qt.rgba(root.theme.foreground.r * 0.9, root.theme.foreground.g * 0.85, root.theme.foreground.b * 0.7, 1)
            opacity: 0.62
        }
    }
    Tape { x: 26; y: -9; src: "tape-a.png"; tilt: -9 }
    Tape { x: root.width - 118; y: -8; src: "tape-b.png"; tilt: 17 }

    // frayed threads off the right-hand tape
    Repeater {
        model: [
            { dx: 4,  len: 12, rot: -6 },
            { dx: 15, len: 15, rot: 3 },
            { dx: 27, len: 10, rot: 9 }
        ]
        delegate: Rectangle {
            required property var modelData
            x: root.width - 104 + modelData.dx
            y: -9
            width: 1
            height: modelData.len
            rotation: modelData.rot
            transformOrigin: Item.Top
            color: Qt.rgba(root.theme.foreground.r, root.theme.foreground.g, root.theme.foreground.b, 0.55)
        }
    }
}
