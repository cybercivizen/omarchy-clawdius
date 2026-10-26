import QtQuick
import qs.Commons
import "Icons.js" as Icons

// Home's right-hand card, with a switcher up top: Limits (the Claude usage
// glance), Timer (timers, alarms, reminders) and Move (the crab's sit-up and
// stand-up-and-walk nudges; their timing is in Settings). Every mode fits one fixed slot, so
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
  // limits | timer | posture
  property string mode: "limits"

  signal modePicked(string mode)
  signal statsOpened()
  signal timerAdded(string kind, string label, double at, double len)
  signal timerCancelled(string id)
  signal nudgeEdited(string key, var patch)
  signal nudged(string key)

  // today's rep, as antirot.py writes it, and the action it's running.
  property var rep: null
  property string antirotBusy: ""
  // Stuck (help with the rep) is a tab only while it's shown: the Stuck?
  // pill on the Anti-rot card opens it, Hide help or another tab closes it.
  readonly property var modes: {
    var m = [
      { id: "limits", name: "LIMITS", icon: Icons.limits },
      { id: "timer", name: "TIMER", icon: Icons.timer },
      { id: "posture", name: "MOVE", icon: Icons.posture }
    ]
    return mode === "stuck" ? m.concat([{ id: "stuck", name: "STUCK", icon: Icons.help }]) : m
  }
  readonly property real pad: pal.sp(18)
  // The content's height in every mode: Limits' two bars set it. Stuck fills
  // whatever height the card is given (the Anti-rot card's) and scrolls.
  readonly property real slot: Style.space(110)

  signal explainAsked(bool again)
  signal hintAsked()

  function modeIndex(id) {
    for (var i = 0; i < modes.length; i++) if (modes[i].id === id) return i
    return -1
  }

  // The new mode's content eases in from the side the tab sits on.
  property int shownIndex: 0
  property string prevMode: mode
  // The tab row reflows when Stuck shows or hides, so the highlight snaps
  // for that instead of gliding along with the shuffle.
  function snapMark() { cornerMark.glide = false; markGlide.restart() }
  Timer { id: markGlide; interval: 80; onTriggered: cornerMark.glide = true }
  onModeChanged: {
    if (mode === "stuck" || prevMode === "stuck") snapMark()
    prevMode = mode
    var i = modeIndex(mode)
    if (visible && i >= 0 && i !== shownIndex) {
      modeSlide.dx = (i > shownIndex ? 1 : -1) * Style.space(10)
      modeSlide.restart()
    }
    if (i >= 0) shownIndex = i
  }
  Slide { id: modeSlide; target: stack }

  implicitHeight: pad * 2 + header.height + pal.sp(14) + slot
  radius: pal.rad(Style.space(24))
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
      text: root.mode === "timer" ? "TIMER" : root.mode === "posture" ? "MOVE" : root.mode === "stuck" ? "STUCK" : "LIMITS"
      textFormat: Text.PlainText
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.8
    }

    TabMark {
      id: cornerMark
      pal: root.pal
      over: switcher.count > 0 ? switcher.itemAt(Math.max(0, root.modeIndex(root.mode))) : null
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Repeater {
        id: switcher
        model: root.modes
        onCountChanged: root.snapMark()

        Rectangle {
          required property var modelData
          readonly property bool current: root.mode === modelData.id
          width: Style.space(26)
          height: Style.space(22)
          radius: pal.pill(height)
          color: root.pal.alpha(root.pal.fg, !current && switchMouse.containsMouse ? 0.06 : 0)
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
    y: root.pad + header.height + root.pal.sp(14)
    width: parent.width - root.pad * 2
    height: root.mode === "stuck" ? Math.max(root.slot, root.height - y - root.pad) : root.slot

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

    Stuck {
      visible: root.mode === "stuck"
      width: parent.width
      height: parent.height
      pal: root.pal
      fontFamily: root.fontFamily
      rep: root.rep
      busy: root.antirotBusy
      onExplainAsked: function(again) { root.explainAsked(again) }
      onHintAsked: root.hintAsked()
    }

  }
}
