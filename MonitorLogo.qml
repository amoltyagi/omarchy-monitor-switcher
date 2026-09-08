// monitor-switcher fork: theme-tinted companion to the README's logo.svg.
import QtQuick
import QtQuick.Shapes

Item {
  id: logo
  property color color: "#ffb16a"
  implicitWidth: 32
  implicitHeight: 32

  Item {
    anchors.centerIn: parent
    width: 32
    height: 32
    scale: Math.min(logo.width, logo.height) / 32

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        strokeColor: Qt.rgba(logo.color.r, logo.color.g, logo.color.b, logo.color.a * 0.55)
        strokeWidth: 2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M11 6V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-1" }
      }
      ShapePath {
        strokeColor: logo.color
        strokeWidth: 2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: "M5 9h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V11a2 2 0 0 1 2-2ZM13 25v4M8 29h10M8 17h10" }
      }
      ShapePath {
        strokeWidth: 0
        fillColor: logo.color
        PathSvg { path: "M17 17a2 2 0 1 1-4 0 2 2 0 0 1 4 0Z" }
      }
    }
  }
}
