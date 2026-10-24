import QtQuick
import qs.Commons

// Eases `target` in from `dx`/`dy` away while it fades up, once per run()
// (the same move viewEnter makes for a whole view). A one-shot, not a loop.
ParallelAnimation {
  id: root

  property Item target: null
  property real dx: 0
  property real dy: 0
  property Translate shift: Translate {}

  onTargetChanged: if (target) target.transform = [shift]

  NumberAnimation { target: root.target; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
  NumberAnimation { target: root.shift; property: "x"; from: root.dx; to: 0; duration: 260; easing.type: Easing.OutQuint }
  NumberAnimation { target: root.shift; property: "y"; from: root.dy; to: 0; duration: 260; easing.type: Easing.OutQuint }
}
