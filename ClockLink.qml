import QtQuick
import "Link.js" as Link

// Loaded by the clock plugin (cybercivizen.clock) through a Loader, so the
// clock keeps working if this plugin is ever removed.
Item {
  function hover(window, hovered) { Link.clockHover(window, hovered) }
  function crabCount() { return Link.count() }
}
