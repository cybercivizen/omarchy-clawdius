import QtQuick
import qs.Commons

// The card-mode switch: the old pane fades out, the new one fades in while
// sliding a few pixels in from the side of the tab that was picked. `shown` is
// the mode whose pane is on screen; bind `visible` to it and `opacity` /
// a Translate to `fade` / `shift`. A one-shot of ~240 ms, not a loop, and it
// does nothing while the card is hidden (`live` false), so no idle redraws.
QtObject {
  id: root

  property string mode: ""
  property var order: []
  property bool live: true
  property real distance: Style.space(10)

  property string shown: mode
  property real fade: 1
  property real shift: 0

  onModeChanged: {
    if (!live || !shown) { swap.stop(); shown = mode; fade = 1; shift = 0; return }
    if (mode === shown) return
    swap.restart()
  }

  property SequentialAnimation swap: SequentialAnimation {
    NumberAnimation { target: root; property: "fade"; to: 0; duration: 70; easing.type: Easing.InQuad }
    ScriptAction {
      script: {
        var dir = root.order.indexOf(root.mode) >= root.order.indexOf(root.shown) ? 1 : -1
        root.shown = root.mode
        root.shift = dir * root.distance
      }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "fade"; to: 1; duration: 170; easing.type: Easing.OutCubic }
      NumberAnimation { target: root; property: "shift"; to: 0; duration: 170; easing.type: Easing.OutCubic }
    }
  }
}
