import QtQuick
import qs.Commons
import "Icons.js" as Icons

// A notification from the feed, drawn in the island: a little Clawd in the
// state's pose with its badge on his corner (green ✓ done, red ✗ failed,
// amber ! needs you, purple z out of usage, teal ↑ sit up), what happened and to which
// session, the point underneath, and a little context on the right.
//
// The island shows it two ways. Closed, it opens just far enough for this
// (`framed: false`, the island is the background). Open, it sits up top
// above the nav as a card of its own, faintly tinted with the state's color.
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // The feed's toast: {kind (done | failed | input | limited | waiting), status, id, name, text, meta, at}
  // or a timer's / the posture nudge's (kind timer | posture | walk), from BarWidget.
  property var toast: null
  property bool framed: true
  // The widest it grows to on its own (as the peek, nothing else sizes it).
  property real maxWidth: Style.space(640)
  readonly property bool hovered: hover.hovered

  signal activated()
  signal dismissed()

  readonly property string kind: toast ? toast.kind : ""
  readonly property color tone: !pal ? "transparent"
    : kind === "done" ? pal.done
    : kind === "failed" ? pal.failed
    : kind === "limited" ? pal.limit
    : kind === "timer" ? pal.crab
    : kind === "posture" || kind === "walk" ? pal.posture
    : pal.needsYou
  readonly property color toneText: !pal ? "transparent" : kind === "waiting" || kind === "input" ? pal.needsYouText : tone
  readonly property string meta: toast && toast.meta ? toast.meta.join("  ·  ") : ""
  readonly property real pad: Style.space(framed ? 14 : 8)

  implicitHeight: Style.space(framed ? 60 : 52)
  implicitWidth: Math.min(maxWidth, Math.max(Style.space(300),
    pad + badge.width + Style.space(12) + Math.max(titleRow.implicitWidth, textLine.implicitWidth)
      + (meta ? Style.space(20) + metaText.implicitWidth : 0) + Style.space(8) + closeButton.width + pad))

  radius: pal.rad(Style.space(20))
  color: framed && pal ? pal.mix(pal.card, tone, pal.light ? 0.06 : 0.08) : "transparent"
  Behavior on color { ColorAnimation { duration: 200 } }

  // The icon: Clawd in the state's pose (hopping, waving, slumped, asleep),
  // gray when it didn't work out, the status badge on his top-left corner.
  // The slot leaves room for the badge poking out past him.
  Item {
    id: badge
    readonly property real overhang: Math.round(crab.badgeSize * 0.35) + Math.max(2, Math.round(crab.badgeSize / 10))
    x: root.pad
    anchors.verticalCenter: parent.verticalCenter
    width: crab.width + overhang
    height: crab.height + overhang

    Crab {
      id: crab
      x: badge.overhang
      y: badge.overhang
      pal: root.pal
      unit: Style.spaceReal(3)
      badgeSize: Style.space(15)
      mood: root.kind === "done" ? "done" : root.kind === "posture" || root.kind === "walk" ? "stretch" : root.kind === "failed" ? "failed"
        : root.kind === "limited" ? "sleep" : "waiting"
      color: !root.pal ? "#D97757" : root.kind === "failed" || root.kind === "limited" ? root.pal.idleCrab : root.pal.crab
      badge: root.kind === "input" ? "waiting" : root.kind === "timer" ? "" : root.kind
      // Ringed in whatever's behind it: the island while peeking, else the card.
      ring: !root.pal ? "black" : root.framed ? root.color : root.pal.island
      fontFamily: root.fontFamily
      animate: root.visible && root.opacity > 0
    }
  }

  Column {
    id: lines
    x: badge.x + badge.width + Style.space(12)
    width: Math.max(0, (root.meta !== "" ? metaText.x - Style.space(20) : closeButton.x - Style.space(8)) - x)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    // "Done · fix the clock"
    Row {
      id: titleRow
      width: Math.min(implicitWidth, parent.width)
      spacing: Style.space(6)
      clip: true

      Text {
        text: root.toast ? root.toast.status : ""
        textFormat: Text.PlainText
        color: root.toneText
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        text: "·"
        textFormat: Text.PlainText
        color: root.pal ? root.pal.dim : "gray"
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        text: root.toast ? root.toast.name : ""
        textFormat: Text.PlainText
        color: root.pal ? root.pal.strong : "white"
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Text {
      id: textLine
      width: parent.width
      text: root.toast ? root.toast.text : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      maximumLineCount: 1
      color: root.pal ? root.pal.muted : "gray"
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    id: metaText
    visible: root.meta !== ""
    x: closeButton.x - Style.space(8) - width
    anchors.verticalCenter: parent.verticalCenter
    text: root.meta
    textFormat: Text.PlainText
    color: root.pal ? root.pal.dim : "gray"
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // The whole thing does what the old desktop toast's click did; × just
  // puts it away. Under the × so that one still gets its own click.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  // Shown while the pointer's on it (the time it's up holds meanwhile).
  Rectangle {
    id: closeButton
    x: root.width - root.pad - width
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(26)
    height: width
    radius: width / 2
    opacity: root.hovered ? 1 : 0
    color: closeMouse.containsMouse && root.pal ? root.pal.alpha(root.pal.fg, 0.10) : "transparent"
    Behavior on opacity { NumberAnimation { duration: 120 } }

    Icon {
      anchors.centerIn: parent
      d: Icons.cross
      size: Style.space(13)
      color: root.pal ? (closeMouse.containsMouse ? root.pal.fg : root.pal.muted) : "white"
    }

    MouseArea {
      id: closeMouse
      anchors.fill: parent
      enabled: root.hovered
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.dismissed()
    }
  }

  HoverHandler {
    id: hover
  }
}
