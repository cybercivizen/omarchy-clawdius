import QtQuick
import qs.Commons

// Two thin rings spreading from the pointer on the screen's edge, like
// GNOME's hot corner; the bar window clips them to half rings. Played once
// per touch (like the island's own morph), so it runs smoothly; nothing loops.
Item {
  id: root

  property color color: "white"
  property real size: Style.space(70)
  property bool fromBottom: false

  // Edge of the window the rings are centred on.
  function play(x, bottom) {
    root.x = x
    fromBottom = bottom
    for (var i = 0; i < rings.count; i++) rings.itemAt(i).run()
  }

  width: 0
  height: 0
  y: fromBottom && parent ? parent.height : 0

  Repeater {
    id: rings
    model: 2

    Rectangle {
      id: ring
      required property int index
      // Resized rather than scaled, so the line stays thin.
      property real d: 8

      width: d
      height: d
      x: -d / 2
      y: -d / 2
      radius: d / 2
      color: "transparent"
      border.width: 1.5
      border.color: root.color
      opacity: 0
      visible: opacity > 0

      function run() { anim.restart() }

      SequentialAnimation {
        id: anim
        // The second ring trails the first.
        PauseAnimation { duration: ring.index * 150 }
        ParallelAnimation {
          NumberAnimation { target: ring; property: "d"; from: 8; to: root.size; duration: 600; easing.type: Easing.OutCubic }
          NumberAnimation { target: ring; property: "opacity"; from: 0.35; to: 0; duration: 600; easing.type: Easing.InQuad }
        }
      }
    }
  }
}
