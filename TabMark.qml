import QtQuick
import qs.Commons

// The highlight behind a row of small tabs: one pill that slides to whichever
// tab is current, instead of each tab lighting up on its own. Put it before
// the row in the same parent; `over` is the current tab's button.
Rectangle {
  id: root

  property QtObject pal
  property Item over: null
  // Off for the first frame after `over` appears, so it lands rather than flies in.
  property bool glide: false

  visible: !!over
  x: over && over.parent ? over.parent.x + over.x : 0
  y: over && over.parent ? over.parent.y + over.y : 0
  width: over ? over.width : 0
  height: over ? over.height : 0
  radius: pal ? pal.pill(height) : height / 2
  color: pal ? pal.alpha(pal.fg, 0.14) : "transparent"

  Behavior on x { enabled: root.glide; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
  Behavior on width { enabled: root.glide; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  Component.onCompleted: Qt.callLater(function() { glide = true })
}
