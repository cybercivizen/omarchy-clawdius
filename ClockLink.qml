import QtQuick
import "Link.js" as Link

// Loaded by a clock plugin through a Loader, so the
// clock keeps working if this plugin is ever removed.
Item {
  id: root

  // Set by the clock; the crab on the same bar window flips `covered` (and
  // sets `ink`, the island's text color) while its island is down over the clock.
  property var barWindow: null
  property bool covered: false
  property color ink: "#000000"

  Component.onCompleted: Link.registerClock(root)
  Component.onDestruction: Link.unregisterClock(root)

  function hover(window, hovered) { Link.clockHover(window, hovered) }
  function click(window) { Link.clockClick(window) }
  function crabCount() { return Link.count() }
}
