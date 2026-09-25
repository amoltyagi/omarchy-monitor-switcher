// A tiny monitor whose thick chin edge shows which way the screen is turned.
// The glyph turns (shortest path) when its angle changes.
import QtQuick

Item {
  id: glyph
  property real angle: 0
  property color color: "white"
  property real strokeWidth: Math.max(1, size * 0.09)
  property real size: 16
  implicitWidth: size
  implicitHeight: size

  Item {
    id: body
    anchors.centerIn: parent
    width: glyph.size * 0.92
    height: glyph.size * 0.64
    rotation: glyph.angle
    Behavior on rotation { RotationAnimation { duration: 260; direction: RotationAnimation.Shortest; easing.type: Easing.OutCubic } }

    Rectangle {
      anchors.fill: parent
      radius: glyph.size * 0.1
      color: "transparent"
      border.width: glyph.strokeWidth
      border.color: glyph.color
      antialiasing: true
    }
    // The chin: the monitor's native bottom bezel.
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.max(glyph.strokeWidth * 2.2, body.height * 0.26)
      radius: glyph.size * 0.08
      color: glyph.color
      antialiasing: true
    }
  }
}
