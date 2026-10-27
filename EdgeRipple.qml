import QtQuick
import QtQuick.Shapes
import qs.Commons

// A soft dark swell spreading from the pointer on the screen's edge, like
// GNOME's hot corner, in the island's own glass: no rings, no outline. The
// bar window clips it to a half disc. It plays once per touch (like the
// island's own morph), so it runs smoothly; nothing loops.
Item {
  id: root

  property color color: "black"
  property real size: Style.space(160)
  property bool fromBottom: false

  // Edge of the window the swell is centred on.
  function play(x, bottom) {
    root.x = x
    fromBottom = bottom
    for (var i = 0; i < swells.count; i++) swells.itemAt(i).run()
  }

  width: 0
  height: 0
  y: fromBottom && parent ? parent.height : 0

  Repeater {
    id: swells
    model: 2

    Shape {
      id: swell
      required property int index
      readonly property real peak: index === 0 ? 0.9 : 0.5

      width: root.size
      height: root.size
      x: -width / 2
      y: -height / 2
      visible: opacity > 0
      opacity: 0
      scale: 0.2
      preferredRendererType: Shape.CurveRenderer

      function run() { anim.restart() }

      SequentialAnimation {
        id: anim
        // The second swell trails the first.
        PauseAnimation { duration: swell.index * 140 }
        ParallelAnimation {
          NumberAnimation { target: swell; property: "scale"; from: 0.2; to: 1; duration: 560; easing.type: Easing.OutCubic }
          SequentialAnimation {
            NumberAnimation { target: swell; property: "opacity"; from: 0; to: swell.peak; duration: 120; easing.type: Easing.OutQuad }
            NumberAnimation { target: swell; property: "opacity"; to: 0; duration: 440; easing.type: Easing.InOutQuad }
          }
        }
      }

      ShapePath {
        strokeColor: "transparent"
        fillGradient: RadialGradient {
          centerX: swell.width / 2
          centerY: swell.height / 2
          centerRadius: swell.width / 2
          focalX: centerX
          focalY: centerY
          GradientStop { position: 0.0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.55) }
          GradientStop { position: 0.45; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.22) }
          GradientStop { position: 1.0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
        }
        PathSvg { path: "M0 0H" + swell.width + "V" + swell.height + "H0Z" }
      }
    }
  }
}
