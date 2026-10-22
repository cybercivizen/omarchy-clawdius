import QtQuick

// Opus Plan's fill: a sweep from one color to the other and back across it,
// drifting sideways while `running`. In steps, like Throb.qml: a per-frame
// sweep would redraw the whole island the whole time it's showing.
Rectangle {
  id: root

  property color from
  property color to
  property real strength: 0.22
  property bool running: false
  property int period: 2400
  property int steps: 20
  property int step: 0

  // A point across it (0 … 1), mixed for the current step.
  function at(p) {
    var k = 0.5 + 0.5 * Math.cos(2 * Math.PI * (p - step / steps))
    return Qt.rgba(from.r + (to.r - from.r) * k, from.g + (to.g - from.g) * k, from.b + (to.b - from.b) * k, strength)
  }

  gradient: Gradient {
    orientation: Gradient.Horizontal
    GradientStop { position: 0; color: root.at(0) }
    GradientStop { position: 0.25; color: root.at(0.25) }
    GradientStop { position: 0.5; color: root.at(0.5) }
    GradientStop { position: 0.75; color: root.at(0.75) }
    GradientStop { position: 1; color: root.at(1) }
  }

  Timer {
    interval: Math.round(root.period / root.steps)
    repeat: true
    running: root.running && root.visible
    onTriggered: root.step = (root.step + 1) % root.steps
  }
}
