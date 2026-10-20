import QtQuick
import QtQuick.Shapes
import Quickshell
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// Home's main card: one moment at a time, the most pressing thing going on
// (BarWidget picks it). A big crab with its badge on the left; then the
// session, what it wants or did, and what you can do about it. The other
// running sessions sit on a rail of small crabs down the right; hovering
// one peeks at it.
//
//   approval  a permission prompt the hook is holding
//   waiting   a session blocked on you without one (a question, input)
//   done      a turn that just finished, until dismissed (or 30s)
//   failed    the same, for one that didn't work out
//   limited   the same, for one stopped by the usage limit: when it resets
//   working   the session being watched: its steps, time and tokens
//   idle      nothing running: start a new chat
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // {kind, session, request, event, more}
  property var moment: null
  property double now: Date.now()
  property bool active: true
  // The rail crabs go with Home, and a HoverHandler destroyed under the
  // pointer never says it was left: without this, the peek and the crab it
  // was on still read as hovered when Home comes back.
  onActiveChanged: if (!active) peek.reset()
  property bool night: false
  property bool sweat: false
  // Running sessions other than the one in the card, and how many didn't fit.
  property var railSessions: []
  property int railMore: 0
  property var requests: []
  property int sessionCount: 0
  // The usage record (Omarchy's collector), for when a hit limit resets.
  property var usage: null

  // answers: AskUserQuestion's, question → chosen label(s).
  signal answered(var request, string choice, var answers)
  signal dismissed()
  // Show a session: its live view for a background one, else its terminal.
  signal opened(var session)
  // Its terminal window, whatever kind it is.
  signal terminal(var session)
  signal newChat()
  signal pinned(var session)
  signal moreSessions()

  readonly property string kind: moment ? moment.kind : "idle"
  readonly property var s: moment && moment.session ? moment.session : null
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property real pad: Style.space(26)
  readonly property bool hasRail: railSessions.length > 0

  readonly property string crabMood: kind === "approval" || kind === "waiting" ? "waiting"
    : kind === "done" ? "done"
    : kind === "failed" ? "failed"
    : kind === "limited" ? "sleep"
    : kind === "working" ? (s && s.thinking ? "thinking" : "typing")
    : night ? "sleep" : "idle"
  readonly property string badge: kind === "approval" || kind === "waiting" ? "waiting"
    : kind === "done" || kind === "failed" || kind === "limited" ? kind
    : kind === "working" ? "working"
    : ""
  // The faint glow along the bottom, in the state's color; none when idle.
  readonly property color glowColor: !pal ? "transparent"
    : kind === "approval" || kind === "waiting" ? pal.needsYou
    : kind === "done" ? pal.done
    : kind === "failed" ? pal.failed
    : kind === "limited" ? pal.limit
    : kind === "working" ? pal.crab
    : "transparent"

  function sessionDot(x) {
    return x.waiting ? pal.needsYou : x.busy ? pal.crab : pal.idleCrab
  }
  function sessionState(x) {
    return x.waiting ? "needs you · " + Format.clock(now, x.turnStart)
      : x.busy ? (x.thinking ? "thinking · " + Format.clock(now, x.turnStart)
                 : Format.clock(now, x.turnStart) + (x.turnTokens ? " · " + Format.tokens(x.turnTokens, " tok") : ""))
      : "idle " + Format.ago(now, x.since)
  }

  radius: Style.space(24)
  color: pal ? pal.card : "transparent"
  border.width: 1
  border.color: pal ? pal.hairline : "transparent"
  implicitHeight: Math.max(Style.space(168), body.implicitHeight + pad * 2, railColumn.implicitHeight + Style.space(20))

  // ---- The glow: a wide arc of the state color rising from the bottom edge,
  //      clipped to the card's rounded corners by drawing it in their shape.
  Shape {
    id: glow
    visible: root.glowColor.a > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 1
    height: Style.space(96)
    preferredRendererType: Shape.CurveRenderer
    readonly property real r: root.radius - 1

    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: glow.width * 0.4
        centerY: glow.height + glow.width * 0.22
        centerRadius: glow.width * 0.42
        focalX: centerX
        focalY: centerY
        GradientStop { position: 0.0; color: Qt.rgba(root.glowColor.r, root.glowColor.g, root.glowColor.b, 0.32) }
        GradientStop { position: 0.55; color: Qt.rgba(root.glowColor.r, root.glowColor.g, root.glowColor.b, 0.12) }
        GradientStop { position: 1.0; color: Qt.rgba(root.glowColor.r, root.glowColor.g, root.glowColor.b, 0) }
      }
      PathSvg {
        path: "M0 0H" + glow.width + "V" + (glow.height - glow.r)
          + "A" + glow.r + " " + glow.r + " 0 0 1 " + (glow.width - glow.r) + " " + glow.height
          + "H" + glow.r + "A" + glow.r + " " + glow.r + " 0 0 1 0 " + (glow.height - glow.r) + "Z"
      }
    }
  }

  // ---- The crab
  Item {
    id: crabSlot
    x: root.pad + Style.space(4)
    anchors.verticalCenter: parent.verticalCenter
    width: crab.implicitWidth
    height: crab.implicitHeight

    Crab {
      id: crab
      pal: root.pal
      unit: Style.spaceReal(6)
      mood: root.crabMood
      color: root.kind === "idle" || root.kind === "failed" || root.kind === "limited" ? root.pal.idleCrab : root.pal.crab
      badge: root.badge
      count: root.kind === "approval" ? root.requests.length : 0
      ring: root.pal.card
      sweat: root.sweat
      animate: root.active
      fontFamily: root.fontFamily
    }

    // Asleep till the limit resets.
    Repeater {
      model: root.kind === "limited" ? 3 : 0
      Text {
        id: zed
        required property int index
        property real t: 0
        x: crab.width * 0.8 + t * Style.space(14) + index * Style.space(4)
        y: -Style.space(4) - t * Style.space(22) - index * Style.space(6)
        opacity: Math.sin(t * Math.PI) * 0.9
        text: "z"
        textFormat: Text.PlainText
        color: root.pal.limit
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle + index * 3
        font.bold: true
        NumberAnimation on t {
          running: root.active && root.kind === "limited"
          from: 0
          to: 1
          duration: 2400
          loops: Animation.Infinite
          onStarted: zed.t = (zed.index * 0.33) % 1
        }
      }
    }

    // Sparkles over a finished turn.
    Repeater {
      model: root.kind === "done" ? 3 : 0
      Text {
        id: spark
        required property int index
        property real t: 0
        x: crab.width * (0.45 + index * 0.2) - width / 2
        y: -Style.space(12) - index % 2 * Style.space(10) - t * Style.space(6)
        opacity: Math.sin(t * Math.PI)
        text: "✦"
        textFormat: Text.PlainText
        color: index === 1 ? root.pal.fg : root.pal.crab
        font.pixelSize: Style.font.subtitle - index % 2 * 3
        NumberAnimation on t {
          running: root.active && root.kind === "done"
          from: 0
          to: 1
          duration: 1400 + spark.index * 250
          loops: Animation.Infinite
        }
      }
    }
  }

  // ---- What the moment says
  Item {
    id: body
    x: crabSlot.x + crabSlot.width + Style.space(28)
    width: (root.hasRail ? rail.x - Style.space(16) : root.width - root.pad) - x
    height: parent.height
    implicitHeight: approval.visible ? approval.implicitHeight
      : limited.visible ? limited.implicitHeight
      : finished.visible ? finished.implicitHeight
      : working.visible ? working.implicitHeight
      : waiting.visible ? waiting.implicitHeight
      : idle.implicitHeight

    Approval {
      id: approval
      visible: root.kind === "approval"
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      pal: root.pal
      fontFamily: root.fontFamily
      request: visible ? root.moment.request : null
      sessionName: visible ? (root.s ? root.s.name : root.moment.name || "") : ""
      background: !!root.s && root.s.kind === "bg"
      more: visible ? root.moment.more || 0 : 0
      onAnswered: function(choice, answers) { root.answered(root.moment.request, choice, answers) }
      onOpened: if (root.s) root.opened(root.s)
    }

    // ---- limited: stopped by the usage limit
    Column {
      id: limited
      visible: root.kind === "limited"
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)
      readonly property var ev: visible ? root.moment.event || {} : {}
      // The limit that's spent, and when it frees up; none on record means
      // only Claude Code's own line (its ev.text) says when.
      readonly property var spent: {
        var limits = (root.usage && root.usage.limits) || []
        var best = null
        for (var i = 0; i < limits.length; i++)
          if (Number(limits[i].percent) >= 0.98 && (!best || Number(limits[i].percent) > Number(best.percent))) best = limits[i]
        return best
      }
      readonly property double remaining: resetsAt - root.now
      readonly property double resetsAt: spent && spent.resetsAt ? new Date(spent.resetsAt).getTime() : 0

      SessionLine {
        dotColor: root.pal.limit
        name: root.s ? root.s.name : limited.ev.name || ""
        background: !!root.s && root.s.kind === "bg"
        caption: "hit the usage limit" + (limited.ev.busyFor ? " · after " + Format.seconds(limited.ev.busyFor) : "")
      }

      Text {
        width: parent.width
        text: limited.remaining > 86400000 ? "Out of usage until " + Qt.formatDateTime(new Date(limited.resetsAt), "ddd h:mm ap") + "."
          : limited.remaining > 0 ? "Out of usage. Back in " + Format.seconds(limited.remaining / 1000).replace(/ \d+s$/, "") + "."
          : "Out of usage for now."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Text {
        visible: !limited.spent && !!limited.ev.text
        width: parent.width
        text: limited.ev.text || ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // How far through the window it is: the bar fills as the reset nears.
      Column {
        visible: !!limited.spent
        width: parent.width
        spacing: Style.space(6)

        Rectangle {
          width: parent.width
          height: Style.space(6)
          radius: height / 2
          color: root.pal.alpha(root.pal.limit, 0.18)

          Rectangle {
            readonly property double windowMs: /week|7-day/i.test(limited.spent ? limited.spent.label || "" : "") ? 7 * 86400000 : 5 * 3600000
            width: parent.width * Math.max(0.03, Math.min(1, 1 - (limited.resetsAt - root.now) / windowMs))
            height: parent.height
            radius: height / 2
            color: root.pal.limit
          }
        }

        Text {
          width: parent.width
          text: (limited.spent ? limited.spent.label + " · " : "")
            + (limited.resetsAt ? "resets " + Qt.formatTime(new Date(limited.resetsAt), "h:mm ap") : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Row {
        spacing: Style.space(8)
        Pill {
          visible: !!root.s && !!root.s.jobId
          pal: root.pal
          fontFamily: root.fontFamily
          label: "Open"
          onClicked: root.opened(root.s)
        }
        Pill {
          pal: root.pal
          fontFamily: root.fontFamily
          kind: "primary"
          label: "OK"
          onClicked: root.dismissed()
        }
      }
    }

    // ---- done / failed
    Column {
      id: finished
      visible: root.kind === "done" || root.kind === "failed"
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)
      readonly property var ev: visible ? root.moment.event || {} : {}

      SessionLine {
        dotColor: root.kind === "done" ? root.pal.done : root.pal.failed
        name: root.s ? root.s.name : finished.ev.name || ""
        background: !!root.s && root.s.kind === "bg"
        caption: (root.kind === "done" ? "finished" : "didn't finish")
          + (finished.ev.busyFor ? " · " + Format.seconds(finished.ev.busyFor) : "")
          + (finished.ev.tokens ? " · " + Format.tokens(finished.ev.tokens) : "")
      }

      Text {
        width: parent.width
        text: finished.ev.text || (root.s && root.s.reply) || (root.kind === "done" ? "All done." : "That one didn't work out.")
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        lineHeight: 1.15
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Row {
        spacing: Style.space(8)
        // A background session opens up close in the island; one in a
        // terminal window only has its terminal to go to.
        Pill {
          visible: !!root.s && !!root.s.jobId
          pal: root.pal
          fontFamily: root.fontFamily
          kind: "primary"
          label: "Open"
          onClicked: root.opened(root.s)
        }
        Pill {
          visible: !!root.s
          pal: root.pal
          fontFamily: root.fontFamily
          kind: root.s && root.s.jobId ? "secondary" : "primary"
          label: "Open terminal"
          onClicked: root.terminal(root.s)
        }
        Pill {
          pal: root.pal
          fontFamily: root.fontFamily
          kind: root.s ? "secondary" : "primary"
          label: "OK"
          onClicked: root.dismissed()
        }
      }
    }

    // ---- working: the watched session's steps
    Column {
      id: working
      visible: root.kind === "working" && !!root.s
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)

      SessionLine {
        dotColor: root.pal.crab
        pulse: true
        name: root.s ? root.s.name : ""
        background: !!root.s && root.s.kind === "bg"
        caption: root.s ? Format.folder(root.s.cwd, root.home) : ""
        elideCaption: Text.ElideMiddle
      }

      Steps {
        id: steps
        visible: items.length > 0
        width: parent.width
        pal: root.pal
        session: root.s
        now: root.now
        fontFamily: root.fontFamily
        animate: root.active
      }

      Text {
        visible: !steps.visible
        width: parent.width
        text: root.s ? (root.s.thinking ? "Thinking…" : root.s.activity || "Working…") : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.italic: true
      }

      Text {
        width: parent.width
        text: root.s ? Format.clock(root.now, root.s.turnStart)
          + (root.s.turnTokens ? " · " + Format.tokens(root.s.turnTokens) : "")
          + (root.s.context && root.s.contextWindow ? " · " + Math.round(100 * root.s.context / root.s.contextWindow) + "% context" : "")
          + ((root.s.children || []).length ? " · " + root.s.children.length + " running alongside" : "") : ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    // ---- waiting on you, without a prompt the card can answer
    Column {
      id: waiting
      visible: root.kind === "waiting" && !!root.s
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(12)

      SessionLine {
        dotColor: root.pal.needsYou
        pulse: true
        name: root.s ? root.s.name : ""
        background: !!root.s && root.s.kind === "bg"
        caption: "needs you" + (root.s && root.s.waitingFor ? " · " + root.s.waitingFor : "")
      }

      Text {
        width: parent.width
        text: root.s && root.s.activity ? root.s.activity : "Claude is waiting for your answer."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Row {
        spacing: Style.space(8)
        Pill {
          pal: root.pal
          fontFamily: root.fontFamily
          kind: "primary"
          label: root.s && root.s.jobId ? "Answer here" : "Open terminal"
          onClicked: root.opened(root.s)
        }
        Pill {
          visible: !!root.s && !!root.s.jobId
          pal: root.pal
          fontFamily: root.fontFamily
          label: "Open terminal"
          onClicked: root.terminal(root.s)
        }
      }
    }

    // ---- idle: nothing running
    Column {
      id: idle
      visible: root.kind === "idle"
      width: parent.width
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(14)

      Column {
        width: parent.width
        spacing: Style.space(5)

        Text {
          width: parent.width
          text: root.night && root.sessionCount === 0 ? "Claude is asleep." : "Nothing running right now."
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.pal.strong
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          width: parent.width
          text: root.sessionCount
            ? root.sessionCount + (root.sessionCount > 1 ? " sessions are" : " session is") + " idle. Start something new, or open one from Sessions."
            : "Start something new, or open an earlier one from Sessions."
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      // Into the chat view (QuickChat): type, Chat or Code, Enter.
      Pill {
        pal: root.pal
        fontFamily: root.fontFamily
        kind: "primary"
        icon: Icons.chat
        label: "New chat"
        onClicked: root.newChat()
      }
    }

    // The watched session itself opens with a click anywhere on it.
    MouseArea {
      visible: working.visible
      anchors.fill: parent
      z: -1
      cursorShape: Qt.PointingHandCursor
      onClicked: root.opened(root.s)
    }
  }

  // ---- The rail: other running sessions as small crabs
  Item {
    id: rail
    visible: root.hasRail
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.top: parent.top
    anchors.topMargin: Style.space(12)
    width: Style.space(48) + Style.space(12)
    height: railColumn.implicitHeight

    Rectangle {
      width: 1
      height: Math.max(railColumn.implicitHeight, root.height - Style.space(24))
      color: root.pal.hairline
    }

    Column {
      id: railColumn
      x: Style.space(12)
      spacing: Style.space(4)

      Repeater {
        // Only while shown: each feed update rebuilds every rail crab.
        model: root.active ? root.railSessions : []

        Rectangle {
          id: railItem
          required property var modelData
          required property int index
          readonly property bool hovered: peek.session && peek.session.id === modelData.id && peek.shown
          width: Style.space(48)
          height: Style.space(34)
          radius: Style.space(12)
          color: hovered ? root.pal.alpha(root.pal.fg, 0.10)
            : modelData.waiting ? root.pal.alpha(root.pal.needsYou, 0.08)
            : "transparent"
          border.width: 1
          border.color: hovered ? root.pal.alpha(root.pal.fg, 0.22)
            : modelData.waiting ? root.pal.alpha(root.pal.needsYou, 0.55)
            : "transparent"

          Clawd {
            anchors.centerIn: parent
            unit: Style.spaceReal(2)
            color: railItem.modelData.busy || railItem.modelData.waiting ? root.pal.crab : root.pal.idleCrab
            mood: railItem.modelData.waiting ? "waiting" : railItem.modelData.busy ? (railItem.modelData.thinking ? "thinking" : "typing") : "idle"
            animate: root.active
          }

          // How long ago it last moved, in a bubble on its corner: since its
          // turn started while it works or waits, since it went idle otherwise.
          Rectangle {
            id: ageChip
            readonly property bool live: railItem.modelData.busy || railItem.modelData.waiting
            readonly property string label: Format.ago(root.now, live ? railItem.modelData.turnStart : railItem.modelData.since)
            visible: label !== ""
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -Style.space(5)
            anchors.topMargin: -Style.space(5)
            width: ageText.implicitWidth + Style.space(5) * 2
            height: ageText.implicitHeight + Style.space(1) * 2
            radius: height / 2
            color: root.pal.raised
            border.width: 1
            border.color: railItem.modelData.waiting ? root.pal.alpha(root.pal.needsYou, 0.6)
              : live ? root.pal.alpha(root.pal.crab, 0.45)
              : root.pal.line

            Text {
              id: ageText
              anchors.centerIn: parent
              text: ageChip.label
              textFormat: Text.PlainText
              color: railItem.modelData.waiting ? root.pal.needsYouText : ageChip.live ? root.pal.crab : root.pal.muted
              font.family: root.fontFamily
              font.pixelSize: Math.round(Style.font.caption * 0.85)
            }
          }

          HoverHandler {
            onHoveredChanged: {
              if (hovered) peek.show(railItem.modelData, railItem.y + railColumn.y + rail.y)
              else peek.leave()
            }
          }

          // One click focuses it (pins it to the card); two open its terminal.
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: clickTimer.restart()
            onDoubleClicked: { clickTimer.stop(); root.terminal(railItem.modelData) }

            Timer {
              id: clickTimer
              interval: 240
              onTriggered: {
                var x = railItem.modelData
                if (x.busy || x.waiting) root.pinned(x)
                else root.opened(x)
              }
            }
          }
        }
      }

      Rectangle {
        visible: root.railMore > 0
        width: Style.space(48)
        height: Style.space(28)
        radius: Style.space(10)
        color: moreMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.08) : "transparent"

        Text {
          anchors.centerIn: parent
          text: "+" + root.railMore
          textFormat: Text.PlainText
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: moreMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.moreSessions()
        }
      }
    }
  }

  // ---- The peek: a rail crab, hovered, slides out a card to its left
  Rectangle {
    id: peek

    property var session: null
    property bool shown: false
    property real anchorY: 0
    readonly property var request: {
      if (!session) return null
      for (var i = 0; i < root.requests.length; i++)
        if (root.requests[i].sessionId === session.id) return root.requests[i]
      return null
    }

    function show(s, y) {
      hideTimer.stop()
      session = s
      anchorY = y
      if (!shown) showTimer.restart()
    }
    function leave() { showTimer.stop(); hideTimer.restart() }
    function reset() { showTimer.stop(); hideTimer.stop(); shown = false; session = null }

    z: 10
    width: Style.space(300)
    height: peekColumn.implicitHeight + Style.space(14) * 2
    x: rail.x - width - Style.space(6) + (shown ? 0 : Style.space(8))
    y: Math.max(Style.space(8), Math.min(anchorY - Style.space(4), root.height - height - Style.space(8)))
    radius: Style.space(16)
    color: root.pal.raised
    border.width: 1
    border.color: root.pal.line
    opacity: shown ? 1 : 0
    visible: opacity > 0 && !!session

    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Timer { id: showTimer; interval: 150; onTriggered: peek.shown = true }
    Timer { id: hideTimer; interval: 220; onTriggered: if (!peekHover.hovered) peek.shown = false }

    HoverHandler {
      id: peekHover
      onHoveredChanged: if (hovered) hideTimer.stop(); else peek.leave()
    }

    Column {
      id: peekColumn
      x: Style.space(16)
      y: Style.space(14)
      width: parent.width - Style.space(16) * 2
      spacing: Style.space(8)

      Item {
        width: parent.width
        height: peekName.implicitHeight

        Row {
          spacing: Style.space(8)
          width: parent.width - peekState.implicitWidth - Style.space(8)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: width
            radius: width / 2
            color: peek.session ? root.sessionDot(peek.session) : "transparent"
          }

          Text {
            id: peekName
            width: Math.min(implicitWidth, parent.width - Style.space(16) - (peekChip.visible ? peekChip.width + Style.space(8) : 0))
            text: peek.session ? peek.session.name : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.pal.strong
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Chip {
            id: peekChip
            visible: !!peek.session && peek.session.kind === "bg"
            anchors.verticalCenter: parent.verticalCenter
            pal: root.pal
            label: "bg"
            fontFamily: root.fontFamily
          }
        }

        Text {
          id: peekState
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: peek.session ? root.sessionState(peek.session) : ""
          textFormat: Text.PlainText
          color: peek.session && peek.session.waiting ? root.pal.needsYouText : root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: !!peek.session && peek.session.waiting
        }
      }

      Text {
        width: parent.width
        text: peek.session ? Format.folder(peek.session.cwd, root.home) : ""
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        text: !peek.session ? ""
          : peek.session.busy || peek.session.waiting ? (peek.session.thinking ? "Thinking…" : peek.session.activity)
          : peek.session.reply ? "Last reply: " + peek.session.reply : peek.session.prompt || ""
        visible: text !== ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: root.pal.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      // A question needs its options: those are on the main card.
      Row {
        visible: !!peek.request && peek.request.tool !== "AskUserQuestion"
        spacing: Style.space(6)
        topPadding: Style.space(2)
        Pill { pal: root.pal; fontFamily: root.fontFamily; compact: true; label: "Deny"; onClicked: root.answered(peek.request, "deny", null) }
        Pill { pal: root.pal; fontFamily: root.fontFamily; compact: true; kind: "primary"; label: "Allow"; onClicked: root.answered(peek.request, "allow", null) }
      }

      Text {
        width: parent.width
        text: "Click to focus · double-click for its terminal"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // The line every moment opens with: state dot, name, `bg` tag, then a caption.
  component SessionLine: Row {
    id: line
    property color dotColor: "transparent"
    property bool pulse: false
    property string name: ""
    property bool background: false
    property string caption: ""
    property int elideCaption: Text.ElideRight
    width: parent ? parent.width : 0
    spacing: Style.space(8)

    Rectangle {
      id: lineDot
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(8)
      height: width
      radius: width / 2
      color: line.dotColor
      SequentialAnimation on opacity {
        running: line.pulse && root.active
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) lineDot.opacity = 1
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, line.width * 0.6)
      text: line.name
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.strong
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Chip {
      visible: line.background
      anchors.verticalCenter: parent.verticalCenter
      pal: root.pal
      label: "bg"
      fontFamily: root.fontFamily
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, line.width - x)
      text: line.caption
      textFormat: Text.PlainText
      elide: line.elideCaption
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
