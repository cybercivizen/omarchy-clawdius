import QtQuick

// Breathes its target's opacity down to `low` and back every `period` ms, in
// a few steps rather than every frame. Any change redraws the whole island,
// and the compositor with it: a 60 fps pulse that never stops kept a laptop's
// GPU busy for a dot. About 7 steps a second still reads as breathing.
// Leaves the target at full strength when it stops.
Timer {
  id: root

  property Item target: null
  property real low: 0.35
  property int period: 1400
  property int steps: 10
  property int step: 0

  interval: Math.round(period / steps)
  repeat: true
  onTriggered: {
    step = (step + 1) % steps
    if (target) target.opacity = low + (1 - low) * (0.5 + 0.5 * Math.cos(2 * Math.PI * step / steps))
  }
  onRunningChanged: if (!running) { step = 0; if (target) target.opacity = 1 }
}
