import QtQuick
import qs.Commons

// Rings spreading from the pointer on the screen's edge, like GNOME's hot
// corner: the bar window clips them to half rings. Stepped rather than
// animated per frame (see Throb.qml): every change redraws the bar.
Item {
  id: root

  property color color: "white"
  property real maxSize: Style.space(56)
  property int steps: 10
  property int step: steps
  property bool fromBottom: false

  // Edge of the window the rings are centred on.
  function play(x, bottom) {
    root.x = x
    fromBottom = bottom
    step = 0
    stepper.restart()
  }

  width: 0
  height: 0
  y: fromBottom && parent ? parent.height : 0
  visible: step < steps

  Timer {
    id: stepper
    interval: 40
    repeat: true
    onTriggered: { root.step++; if (root.step >= root.steps) stop() }
  }

  Repeater {
    model: 3
    Rectangle {
      required property int index
      // Each ring trails the one before it by two steps.
      readonly property real t: Math.max(0, Math.min(1, (root.step - index * 2) / 6))
      readonly property real eased: 1 - Math.pow(1 - t, 2)
      visible: t > 0 && t < 1
      width: root.maxSize * eased
      height: width
      x: -width / 2
      y: -height / 2
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.7 * (1 - t))
    }
  }
}
