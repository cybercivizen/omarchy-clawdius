import QtQuick

// Turns its target a full circle every `period` ms in `steps` ticks, like a
// classic spinner, instead of every frame (see Throb.qml for why).
Timer {
  id: root

  property Item target: null
  property int period: 900
  property int steps: 12

  interval: Math.round(period / steps)
  repeat: true
  onTriggered: if (target) target.rotation = (target.rotation + 360 / steps) % 360
}
