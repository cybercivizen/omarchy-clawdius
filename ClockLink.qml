import QtQuick
import "Link.js" as Link

// Loaded by a clock plugin through a Loader, so the
// clock keeps working if this plugin is ever removed.
Item {
  id: root
  // The bar window the clock sits in, set by the clock.
  property var barWindow: null
  // The island is down over the clock: draw the time in `ink`, not the bar's color.
  property bool covered: false
  property color ink: "#000000"

  function hover(window, hovered) { Link.clockHover(window, hovered) }
  function click(window) { Link.clockClick(window) }
  function crabCount() { return Link.count() }

  // Stepped, not per-frame: the island opens and closes a few times a minute.
  Timer {
    interval: 100
    running: !!root.barWindow
    repeat: true
    onTriggered: {
      var c = Link.cover(root.barWindow)
      root.covered = c !== null
      if (c !== null) root.ink = c
    }
  }
}
