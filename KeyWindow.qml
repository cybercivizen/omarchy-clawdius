import QtQuick
import Quickshell
import Quickshell.Wayland

// The card is an xdg-popup of the bar, and the bar never takes the keyboard,
// so nothing typed into the card arrives. This is a 1×1, click-through
// layer surface that does take it (the shell's KeyboardPanel trick: an
// Exclusive prime, then OnDemand so clicking another window still moves
// focus away). It holds the live terminal's real text field; LiveTerm only
// draws that field's text and caret.
//
// Opened from the keyboard (`cover`), the pointer can be anywhere, and going
// OnDemand hands the keyboard to whatever surface is under it. So then it
// covers the screen, see-through, with the bar and the card cut out of its
// input (the shell's KeyboardPanel does the same): the surface under the
// pointer is this one, and a click outside lands here and closes.
PanelWindow {
  id: root

  // Wanted while a live terminal is showing; prime() grabs focus again.
  property bool wanted: false
  property bool primed: false
  property bool cover: false
  // In this window's coordinates (the monitor's): the card, and the bar strip.
  property rect hole: Qt.rect(0, 0, 0, 0)
  property real barHeight: 0
  signal outsideClicked()
  // LiveTerm's key filter: return true to eat the key instead of typing it.
  property var handler: null
  readonly property alias field: field
  // Set by LiveTerm to match the text it draws.
  property real fieldWidth: 100
  property bool fieldWrap: true
  property int fontSize: 12

  // Just after a prime, the pointer's whereabouts can't be trusted: an
  // Exclusive layer takes the pointer too, and a click made meanwhile keeps
  // it here till the button comes up. A pointer leave then isn't one.
  readonly property bool settling: settleTimer.running

  function prime() {
    if (!wanted) return
    primed = false
    primeTimer.restart()
    settleTimer.restart()
    Qt.callLater(function() { field.forceActiveFocus() })
  }

  visible: wanted
  color: "transparent"
  implicitWidth: 1
  implicitHeight: 1
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; left: true; right: cover; bottom: cover }
  mask: Region {
    item: root.cover ? coverArea : null
    Region { intersection: Intersection.Subtract; width: root.width; height: root.barHeight }
    Region { intersection: Intersection.Subtract; x: root.hole.x; y: root.hole.y; width: root.hole.width; height: root.hole.height }
  }

  WlrLayershell.namespace: "clawdius-keys"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: wanted ? (primed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None

  onWantedChanged: if (wanted) prime(); else { primeTimer.stop(); settleTimer.stop(); primed = false }

  Timer {
    id: primeTimer
    interval: 75
    onTriggered: if (root.wanted) root.primed = true
  }

  Timer {
    id: settleTimer
    interval: 450
  }

  // Off-surface but laid out like the text LiveTerm draws, so its
  // cursorRectangle lines up with the drawing.
  MouseArea {
    id: coverArea
    anchors.fill: parent
    enabled: root.cover
    onPressed: root.outsideClicked()
  }

  TextEdit {
    id: field
    focus: true
    // Never drawn: with `cover` the window spans the screen.
    opacity: 0
    width: root.fieldWidth
    font.family: "monospace"
    font.pixelSize: root.fontSize
    wrapMode: root.fieldWrap ? TextEdit.Wrap : TextEdit.NoWrap
    textFormat: TextEdit.PlainText
    Keys.onPressed: function(event) { if (root.handler && root.handler(event)) event.accepted = true }
  }
}
