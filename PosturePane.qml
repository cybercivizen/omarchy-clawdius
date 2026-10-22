import QtQuick
import qs.Commons
import "Icons.js" as Icons
import "Timers.js" as Timers

// The Posture mode of Home's corner card: a crab that nudges you to sit up
// every so often. It sits tall while there's time, slumps as the nudge gets
// near, and the toast that rings it (BarWidget) has it hop. Off, it sleeps,
// and it dozes while you're away from the keyboard: the count waits for you.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // {on, everyMin, nextAt, awaySince, pausedLeft, rested}
  property var posture: ({ on: false, everyMin: 30, nextAt: 0, awaySince: 0, pausedLeft: 0, rested: false })
  property double now: Date.now()

  // A patch of the posture settings (on / everyMin).
  signal edited(var patch)
  signal nudged()

  readonly property bool on: !!posture.on
  // Away: BarWidget froze the count (awaySince) and kept what was left.
  readonly property bool away: on && posture.awaySince > 0
  readonly property double leftMs: !on ? 0 : away ? posture.pausedLeft : Math.max(0, posture.nextAt - now)
  // 20 and 30 are chips; anything else is the custom stepper's.
  property bool custom: false
  readonly property bool customShown: custom || (posture.everyMin !== 20 && posture.everyMin !== 30)
  readonly property real span: Math.max(1, posture.everyMin * 60000)
  readonly property bool slumping: on && !away && leftMs < Math.min(120000, span * 0.2)
  // Shown line: changes each interval, not each repaint.
  readonly property string line: Timers.postureLine(Math.round(posture.nextAt / 60000))

  implicitHeight: body.implicitHeight

  Column {
    id: body
    width: parent.width
    spacing: Style.space(12)

    Row {
      width: parent.width
      spacing: Style.space(12)

      Crab {
        id: crab
        anchors.verticalCenter: parent.verticalCenter
        pal: root.pal
        unit: Style.spaceReal(3)
        mood: !root.on || root.away ? "sleep" : root.slumping ? "failed" : "idle"
        color: root.on && !root.away && !root.slumping ? root.pal.crab : root.pal.idleCrab
        ring: root.pal.card
        fontFamily: root.fontFamily
        animate: root.visible
      }

      Column {
        width: parent.width - crab.width - Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Text {
          width: parent.width
          text: !root.on ? "Posture check is off." : root.away ? "Paused while you're away."
            : root.slumping ? "Slouching… sit up!" : root.posture.rested ? "Fresh start after your break." : root.line
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
          color: root.pal.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          width: parent.width
          text: root.on ? (root.away ? "waiting at " : "next nudge in ") + Timers.left(root.leftMs + 999) : "a nudge every " + root.posture.everyMin + " min"
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // Time to the next nudge, filling up.
    Rectangle {
      visible: root.on
      width: parent.width
      height: Style.space(3)
      radius: height / 2
      color: root.pal.alpha(root.pal.fg, 0.12)

      Rectangle {
        height: parent.height
        radius: height / 2
        width: parent.width * (1 - Math.min(1, root.leftMs / root.span))
        color: root.slumping ? root.pal.crab : root.pal.fg
      }
    }

    Row {
      spacing: Style.space(6)

      Repeater {
        model: Timers.intervals

        Rectangle {
          required property int modelData
          width: intervalText.implicitWidth + Style.space(18)
          height: Style.space(24)
          radius: height / 2
          color: !root.customShown && root.posture.everyMin === modelData ? root.pal.alpha(root.pal.fg, 0.14) : root.pal.alpha(root.pal.fg, intervalMouse.containsMouse ? 0.08 : 0.04)

          Text {
            id: intervalText
            anchors.centerIn: parent
            text: parent.modelData + "m"
            textFormat: Text.PlainText
            color: !root.customShown && root.posture.everyMin === parent.modelData ? root.pal.strong : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          MouseArea {
            id: intervalMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.custom = false; root.edited({ everyMin: parent.modelData }) }
          }
        }
      }

      Rectangle {
        width: customText.implicitWidth + Style.space(18)
        height: Style.space(24)
        radius: height / 2
        color: root.customShown ? root.pal.alpha(root.pal.fg, 0.14) : root.pal.alpha(root.pal.fg, customMouse.containsMouse ? 0.08 : 0.04)

        Text {
          id: customText
          anchors.centerIn: parent
          text: "Custom"
          textFormat: Text.PlainText
          color: root.customShown ? root.pal.strong : root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: customMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.custom = true
        }
      }

      Pill {
        pal: root.pal
        compact: true
        kind: root.on ? "secondary" : "primary"
        label: root.on ? "Off" : "Start"
        onClicked: root.edited({ on: !root.on })
      }
    }

    // The custom wait, 5 to 120 minutes.
    Item {
      visible: root.customShown
      width: parent.width
      height: Style.space(30)

      Pill {
        pal: root.pal
        compact: true
        iconOnly: true
        icon: Icons.minus
        onClicked: root.edited({ everyMin: Math.max(5, Timers.step(root.posture.everyMin, -1)) })
      }

      Text {
        anchors.centerIn: parent
        text: "every " + Timers.span(root.posture.everyMin)
        textFormat: Text.PlainText
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Pill {
        anchors.right: parent.right
        pal: root.pal
        compact: true
        iconOnly: true
        icon: Icons.plus
        onClicked: root.edited({ everyMin: Math.min(120, Timers.step(root.posture.everyMin, 1)) })
      }
    }

    Text {
      visible: root.on
      text: "Nudge me now"
      textFormat: Text.PlainText
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.underline: nowMouse.containsMouse

      MouseArea {
        id: nowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.nudged()
      }
    }
  }
}
