import QtQuick
import qs.Commons

// Clawd with a status badge on its shoulder: amber "!" waiting on you, green
// ✓ done, red ✗ failed, purple z out of usage, teal ↑ sit up (posture), and
// three orange dots while it works. The badge is ringed in the island's color so it reads as sitting on top of the crab.
Item {
  id: root

  property QtObject pal
  property string mood: "idle"
  property real unit: 6
  property color color: pal ? pal.crab : "#D97757"
  property bool sweat: false
  property bool animate: true
  // "" | "working" | "waiting" | "done" | "failed" | "limited" | "posture" | "walk"
  property string badge: ""
  // Shown in the waiting badge when more than one thing waits.
  property int count: 0
  property color ring: pal ? pal.card : "black"
  property string fontFamily: Style.font.family
  readonly property alias step: clawd.step

  implicitWidth: clawd.implicitWidth
  implicitHeight: clawd.implicitHeight

  Clawd {
    id: clawd
    unit: root.unit
    color: root.color
    mood: root.mood
    sweat: root.sweat
    animate: root.animate

    // Bob along while typing, hop while celebrating, sag when it failed.
    transform: Translate {
      y: clawd.mood === "typing" && clawd.step % 2 === 1 ? -root.unit * 0.5
        : clawd.mood === "done" && clawd.step % 2 === 0 ? -root.unit
        : clawd.mood === "failed" ? root.unit * 0.5
        : 0
    }
  }

  // Scales with the crab; a small crab can ask for a bigger, readable one.
  property real badgeSize: Math.max(10, Math.round(unit * 3.6))
  readonly property bool dots: badge === "working"

  Rectangle {
    id: badgeRing
    visible: root.badge !== "" && !!root.pal
    readonly property real ringWidth: Math.max(2, Math.round(root.badgeSize / 10))
    x: -Math.round(root.badgeSize * 0.35) - ringWidth
    y: -Math.round(root.badgeSize * 0.35) - ringWidth
    width: badgeFill.width + ringWidth * 2
    height: badgeFill.height + ringWidth * 2
    radius: height / 2
    color: root.ring

    Rectangle {
      id: badgeFill
      x: badgeRing.ringWidth
      y: badgeRing.ringWidth
      height: root.badgeSize
      width: root.dots ? Math.round(root.badgeSize * 1.7) : Math.max(height, glyph.implicitWidth + Math.round(root.badgeSize * 0.4))
      radius: height / 2
      color: !root.pal ? "transparent"
        : root.badge === "waiting" ? root.pal.needsYou
        : root.badge === "done" ? root.pal.done
        : root.badge === "failed" ? root.pal.failed
        : root.badge === "limited" ? root.pal.limit
        : root.badge === "posture" || root.badge === "walk" ? root.pal.posture
        : root.pal.mix(root.pal.card, root.pal.fg, 0.12)

      Text {
        id: glyph
        visible: !root.dots
        anchors.centerIn: parent
        text: root.badge === "waiting" ? (root.count > 1 ? String(root.count) : "!")
          : root.badge === "done" ? "✓"
          : root.badge === "failed" ? "✗"
          : root.badge === "limited" ? "z"
          : root.badge === "posture" ? "↑"
          : root.badge === "walk" ? "→"
          : ""
        textFormat: Text.PlainText
        color: root.pal ? root.pal.onFill(badgeFill.color) : "white"
        font.family: root.fontFamily
        font.pixelSize: Math.round(root.badgeSize * 0.62)
        font.bold: true
      }

      // Three dots that light up in turn, like a typing indicator.
      Row {
        visible: root.dots
        anchors.centerIn: parent
        spacing: Math.max(1, Math.round(root.badgeSize * 0.12))

        Repeater {
          model: 3
          Rectangle {
            required property int index
            width: Math.max(2, Math.round(root.badgeSize * 0.2))
            height: width
            radius: width / 2
            color: root.pal ? root.pal.crab : "orange"
            opacity: dotTimer.lit === index ? 1 : 0.4
          }
        }
      }

      Timer {
        id: dotTimer
        property int lit: 0
        running: root.dots && root.animate && root.visible
        interval: 300
        repeat: true
        onTriggered: lit = (lit + 1) % 3
      }
    }
  }
}
