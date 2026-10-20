import QtQuick
import QtQuick.Shapes

// A stroked line icon from an SVG path on a 24×24 grid (the mockups' icons,
// drawn as is rather than looked up in the font).
Shape {
  id: root

  property string d: ""
  property real size: 16
  property color color: "white"
  property real stroke: 2

  width: size
  height: size
  preferredRendererType: Shape.CurveRenderer

  ShapePath {
    scale: Qt.size(root.size / 24, root.size / 24)
    strokeColor: root.color
    strokeWidth: root.stroke * root.size / 24
    fillColor: "transparent"
    capStyle: ShapePath.RoundCap
    joinStyle: ShapePath.RoundJoin
    PathSvg { path: root.d }
  }
}
