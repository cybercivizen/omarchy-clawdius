import QtQuick
import qs.Commons
import "Icons.js" as Icons

// Home's right-hand card, with a switcher up top: Limits (the Claude usage
// glance), Timer (timers, alarms, reminders), Move (the crab's sit-up and
// stand-up-and-walk nudges; their timing is in Settings) and Anti-rot
// (today's challenges and progress). Every mode fits one fixed slot, so
// switching never moves the island. The mode is remembered (the Move tab
// is mode "posture"); the engine behind the timers and nudges is in BarWidget.
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property double now: Date.now()
  property var record: null
  property var timers: []
  property var posture: ({ on: false, everyMin: 30, nextAt: 0 })
  property var walk: ({ on: false, everyMin: 60, nextAt: 0 })
  // antirot.json, as antirot.py writes it, and the action running.
  property var antirot: null
  property string antirotBusy: ""
  // limits | timer | posture | antirot
  property string mode: "limits"

  signal modePicked(string mode)
  signal statsOpened()
  signal timerAdded(string kind, string label, double at, double len)
  signal timerCancelled(string id)
  signal nudgeEdited(string key, var patch)
  signal nudged(string key)
  signal challenge(string action)

  readonly property var modes: [
    { id: "limits", name: "LIMITS", icon: Icons.limits },
    { id: "timer", name: "TIMER", icon: Icons.timer },
    { id: "posture", name: "MOVE", icon: Icons.posture },
    { id: "antirot", name: "ANTI-ROT", icon: Icons.code }
  ]
  readonly property real pad: Style.space(18)
  // The content's height in every mode: Limits' two bars set it.
  readonly property real slot: Style.space(110)

  implicitHeight: pad * 2 + header.height + Style.space(14) + slot
  radius: Style.space(24)
  color: pal ? pal.card : "transparent"
  border.width: 1
  border.color: pal ? pal.hairline : "transparent"

  Item {
    id: header
    x: root.pad
    y: root.pad
    width: parent.width - root.pad * 2
    height: Style.space(22)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.mode === "timer" ? "TIMER" : root.mode === "posture" ? "MOVE" : root.mode === "antirot" ? "ANTI-ROT" : "LIMITS"
      textFormat: Text.PlainText
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.8
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Repeater {
        model: root.modes

        Rectangle {
          required property var modelData
          readonly property bool current: root.mode === modelData.id
          width: Style.space(26)
          height: Style.space(22)
          radius: height / 2
          color: current ? root.pal.alpha(root.pal.fg, 0.14) : root.pal.alpha(root.pal.fg, switchMouse.containsMouse ? 0.06 : 0)
          Behavior on color { ColorAnimation { duration: 120 } }

          Icon {
            anchors.centerIn: parent
            d: parent.modelData.icon
            size: Style.space(13)
            color: parent.current ? root.pal.strong : root.pal.muted
          }

          MouseArea {
            id: switchMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.modePicked(parent.modelData.id)
          }
        }
      }
    }
  }

  Item {
    id: stack
    x: root.pad
    y: root.pad + header.height + Style.space(14)
    width: parent.width - root.pad * 2
    height: root.slot

    Glance {
      id: glance
      visible: root.mode === "limits"
      width: parent.width
      pal: root.pal
      record: root.record
      now: root.now
      fontFamily: root.fontFamily
      onActivated: root.statsOpened()
    }

    TimerPane {
      id: timerPane
      visible: root.mode === "timer"
      width: parent.width
      pal: root.pal
      fontFamily: root.fontFamily
      timers: root.timers
      now: root.now
      onAdded: function(kind, label, at, len) { root.timerAdded(kind, label, at, len) }
      onCancelled: function(id) { root.timerCancelled(id) }
    }

    PosturePane {
      id: posturePane
      visible: root.mode === "posture"
      width: parent.width
      pal: root.pal
      fontFamily: root.fontFamily
      posture: root.posture
      walk: root.walk
      now: root.now
      onEdited: function(key, patch) { root.nudgeEdited(key, patch) }
      onNudged: function(key) { root.nudged(key) }
    }

    AntirotPane {
      id: antirotPane
      visible: root.mode === "antirot"
      width: parent.width
      pal: root.pal
      fontFamily: root.fontFamily
      antirot: root.antirot
      busy: root.antirotBusy
      onChallenge: function(action) { root.challenge(action) }
    }
  }
}
