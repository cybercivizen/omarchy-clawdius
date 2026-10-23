import QtQuick
import qs.Commons
import "Timers.js" as Timers

// The Move mode of Home's corner card: a crab that nudges you to sit up and
// to stand up and walk, each on its own clock. It sits tall while there's
// time, slumps as a nudge gets near, and the toast that rings it (BarWidget)
// has it hop. Off, it sleeps, and it dozes while you're away from the
// keyboard: the counts wait for you. How often each one rings is in Settings.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // {on, everyMin, nextAt, awaySince, pausedLeft, rested}
  property var posture: ({ on: false, everyMin: 30, nextAt: 0, awaySince: 0, pausedLeft: 0, rested: false })
  property var walk: ({ on: false, everyMin: 60, nextAt: 0, awaySince: 0, pausedLeft: 0, rested: false })
  property double now: Date.now()

  // A patch of one nudge's state ("posture" | "walk"): on.
  signal edited(string key, var patch)
  signal nudged(string key)

  readonly property bool anyOn: !!posture.on || !!walk.on
  readonly property bool away: (!!posture.on && posture.awaySince > 0) || (!!walk.on && walk.awaySince > 0)
  readonly property bool rested: (!!posture.on && !!posture.rested) || (!!walk.on && !!walk.rested)
  readonly property bool slumping: slump(posture) || slump(walk)
  // The one that rings first: what the crab's click and the aside line go by.
  readonly property string nearest: !posture.on ? "walk" : !walk.on ? "posture" : leftOf(posture) <= leftOf(walk) ? "posture" : "walk"
  // Shown line: changes each interval, not each repaint.
  readonly property string line: nearest === "walk" ? Timers.walkLine(Math.round(walk.nextAt / 60000)) : Timers.postureLine(Math.round(posture.nextAt / 60000))

  implicitHeight: body.implicitHeight

  function leftOf(n) { return !n.on ? 0 : n.awaySince > 0 ? n.pausedLeft : Math.max(0, n.nextAt - now) }
  function slump(n) { return !!n.on && !(n.awaySince > 0) && leftOf(n) < Math.min(120000, Math.max(1, n.everyMin * 60000) * 0.2) }

  // One reminder: its name, the time to it, a bar filling up and the switch.
  component Nudge: Item {
    id: nudge
    property string key: ""
    property string title: ""
    property var info: ({})
    readonly property bool on: !!info.on
    readonly property bool away: on && info.awaySince > 0
    readonly property real leftMs: root.leftOf(info)
    readonly property real span: Math.max(1, (info.everyMin || 1) * 60000)

    width: parent.width
    height: Style.space(36)

    Text {
      id: titleText
      text: nudge.title
      textFormat: Text.PlainText
      color: nudge.on ? root.pal.fg : root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: nudge.on
    }

    Text {
      anchors.left: titleText.right
      anchors.leftMargin: Style.space(8)
      anchors.right: toggle.left
      anchors.rightMargin: Style.space(6)
      anchors.baseline: titleText.baseline
      text: !nudge.on ? "every " + Timers.span(nudge.info.everyMin || 0) : nudge.away ? "paused" : Timers.left(nudge.leftMs + 999)
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Pill {
      id: toggle
      anchors.right: parent.right
      pal: root.pal
      dense: true
      fontFamily: root.fontFamily
      kind: nudge.on ? "secondary" : "primary"
      label: nudge.on ? "Off" : "Start"
      onClicked: root.edited(nudge.key, { on: !nudge.on })
    }

    // Time to the next nudge, filling up.
    Rectangle {
      visible: nudge.on
      anchors.bottom: parent.bottom
      width: parent.width
      height: Style.space(3)
      radius: height / 2
      color: root.pal.alpha(root.pal.fg, 0.12)

      Rectangle {
        height: parent.height
        radius: height / 2
        width: parent.width * (1 - Math.min(1, nudge.leftMs / nudge.span))
        color: root.slump(nudge.info) ? root.pal.crab : root.pal.fg
      }
    }
  }

  Row {
    id: body
    width: parent.width
    spacing: Style.space(12)

    Item {
      id: crabSlot
      width: crab.width
      height: Style.space(56)
      anchors.verticalCenter: parent.verticalCenter

      Crab {
        id: crab
        anchors.centerIn: parent
        pal: root.pal
        unit: Style.spaceReal(3)
        mood: !root.anyOn || root.away ? "sleep" : root.slumping ? "failed" : "idle"
        color: root.anyOn && !root.away && !root.slumping ? root.pal.crab : root.pal.idleCrab
        ring: root.pal.card
        fontFamily: root.fontFamily
        animate: root.visible
      }

      // The crab is the "nudge me now" button.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.nudged(root.nearest)
      }
    }

    Column {
      width: parent.width - crabSlot.width - Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Nudge { key: "posture"; title: "Sit up"; info: root.posture }
      Nudge { key: "walk"; title: "Walk"; info: root.walk }

      Text {
        width: parent.width
        text: !root.anyOn ? "Both nudges are off."
          : root.away ? "Paused while you're away."
          : root.slumping ? "Slouching… move!"
          : root.rested ? "Fresh start after your break."
          : root.line
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
