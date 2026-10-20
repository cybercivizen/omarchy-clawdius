import QtQuick
import QtQuick.Shapes

// Google's "G" in its four colors, for the search view's /g chip: a ring
// open at the top right, and the bar into its middle.
Shape {
  id: root

  property real size: 16
  readonly property real w: size * 0.2
  readonly property real r: (size - w) / 2
  readonly property real c: size / 2

  width: size
  height: size
  preferredRendererType: Shape.CurveRenderer

  component Arc: ShapePath {
    id: arc
    property real from: 0
    property real sweep: 0
    strokeWidth: root.w
    fillColor: "transparent"
    capStyle: ShapePath.FlatCap
    PathAngleArc {
      centerX: root.c
      centerY: root.c
      radiusX: root.r
      radiusY: root.r
      startAngle: arc.from
      sweepAngle: arc.sweep
    }
  }

  Arc { strokeColor: "#4285F4"; from: 0; sweep: 45 }
  Arc { strokeColor: "#34A853"; from: 45; sweep: 90 }
  Arc { strokeColor: "#FBBC05"; from: 135; sweep: 75 }
  Arc { strokeColor: "#EA4335"; from: 210; sweep: 105 }

  ShapePath {
    strokeColor: "#4285F4"
    strokeWidth: root.w
    fillColor: "transparent"
    capStyle: ShapePath.FlatCap
    startX: root.c
    startY: root.c
    PathLine { x: root.c + root.r + root.w / 2; y: root.c }
  }
}
