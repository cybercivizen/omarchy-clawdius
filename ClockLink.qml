import QtQuick
import "Link.js" as Link

// Loaded by a clock plugin through a Loader, so the
// clock keeps working if this plugin is ever removed.
Item {
  function hover(window, hovered) { Link.clockHover(window, hovered) }
  function click(window) { Link.clockClick(window) }
  function crabCount() { return Link.count() }
}
