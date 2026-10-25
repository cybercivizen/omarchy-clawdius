import QtQuick
import Quickshell
import qs.Commons
import "Format.js" as Format

// Sessions → Live: every running session, waiting on you first, then busy,
// then idle. Each row: a small crab in the session's state, its name, the
// `bg` tag and folder, and how it stands on the right; under that, what it
// is doing this second or the last thing it said. A background row opens
// its live view; a terminal row brings the terminal forward.
Column {
  id: root

  property QtObject pal
  property var sessions: []
  property int hiddenIdle: 0
  // Idle sessions in all (before the cut), the cut itself, and whether it is lifted.
  property int idleCount: 0
  property int idleLimit: 4
  property bool idleExpanded: false
  property double now: Date.now()
  property bool active: true
  property string fontFamily: Style.font.family
  // The background session open in the detail view, if any.
  property string liveId: ""
  // Job id → why the last sleep sweep left it running, and when idle ones go.
  property var awake: ({})
  property int idleStopMinutes: 30
  property string emptyText: "No Claude sessions running.\nStart one with + above."

  // A row was clicked.
  signal opened(var session)
  // Stop on an idle background row: end its process, keep the conversation.
  signal stopRequested(var session)
  signal idleToggled()
  // The pin button on a row: toggle it pinned.
  signal starRequested(var session)
  // Ids of pinned sessions (prefs.json).
  property var starredIds: []

  readonly property string home: Quickshell.env("HOME") || ""

  spacing: Style.space(2)

  function childSummary(children, queued) {
    var agents = children.filter(function(c) { return c.kind === "agent" }).length
    var shells = children.length - agents
    var parts = []
    if (agents) parts.push(agents + (agents > 1 ? " agents" : " agent"))
    if (shells) parts.push(shells + (shells > 1 ? " shells" : " shell"))
    if (parts.length) parts[parts.length - 1] += " running"
    if (queued) parts.push(queued + " queued")
    return parts.join(" · ")
  }

  // Why an idle background session hasn't gone to sleep yet, in a few words.
  function awakeLine(s) {
    var why = s.jobId ? awake[s.jobId] : ""
    if (why === "recent") {
      var left = Math.ceil(idleStopMinutes - (now - s.since) / 60000)
      return "sleeps in ~" + Math.max(1, left) + "m"
    }
    return { attached: "kept: terminal attached", "background work": "kept: background work",
      "pending wakeup / monitor / cron": "kept: wakeup or cron pending", protected: "kept: work alongside" }[why] || ""
  }

  Text {
    visible: root.sessions.length === 0 && root.emptyText !== ""
    width: parent.width
    topPadding: Style.space(14)
    bottomPadding: Style.space(14)
    horizontalAlignment: Text.AlignHCenter
    text: root.emptyText
    textFormat: Text.PlainText
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    // Rows only while shown: each feed update hands over a new list, and
    // the Repeater rebuilds every row for it, island closed or not.
    model: root.active ? root.sessions : []

    Item {
      id: sessionRow
      required property var modelData
      required property int index
      readonly property var s: modelData
      readonly property bool live: !!s.jobId && s.jobId === root.liveId
      readonly property bool stoppable: s.kind === "bg" && !!s.jobId && !s.busy && !s.waiting && !live
      readonly property bool lively: s.busy || s.waiting
      readonly property real padH: Style.space(14)
      readonly property real padV: Style.space(11)
      width: root.width
      height: rowColumn.implicitHeight + padV * 2

      // Hover to see it's clickable; a session waiting on you stays lit.
      Rectangle {
        anchors.fill: parent
        radius: pal.rad(Style.space(16))
        color: sessionRow.s.waiting ? root.pal.alpha(root.pal.needsYou, rowMouse.containsMouse ? 0.14 : 0.08)
          : root.pal.alpha(root.pal.fg, rowMouse.containsMouse ? 0.07 : sessionRow.s.busy ? 0.04 : 0)
        border.width: sessionRow.s.waiting || sessionRow.live ? 1 : 0
        border.color: sessionRow.s.waiting ? root.pal.alpha(root.pal.needsYou, 0.30) : root.pal.alpha(root.pal.crab, 0.45)
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.opened(sessionRow.s)
      }

      Row {
        x: sessionRow.padH
        y: sessionRow.padV
        width: parent.width - sessionRow.padH * 2
        spacing: Style.space(14)

        // Centred on the row's two lines.
        Item {
          width: Style.space(36)
          height: rowColumn.height

          Clawd {
            anchors.centerIn: parent
            unit: Style.spaceReal(2)
            color: sessionRow.lively ? root.pal.crab : root.pal.idleCrab
            mood: sessionRow.s.waiting ? "waiting" : sessionRow.s.busy ? (sessionRow.s.thinking ? "thinking" : "typing") : "idle"
            animate: root.active
          }
        }

        Column {
          id: rowColumn
          width: parent.width - x
          spacing: Style.space(5)

          // Name, `bg` and folder on the left; how it stands on the right.
          Item {
            width: parent.width
            height: nameText.implicitHeight

            Row {
              spacing: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: nameText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, rowColumn.width - whenText.implicitWidth - pinButton.width - Style.space(90))
                text: sessionRow.s.name
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: sessionRow.lively || sessionRow.live ? root.pal.strong : root.pal.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: sessionRow.lively || sessionRow.live
              }

              Chip {
                visible: sessionRow.s.kind === "bg"
                anchors.verticalCenter: parent.verticalCenter
                pal: root.pal
                label: sessionRow.live ? "▾ bg" : "bg"
                fontFamily: root.fontFamily
              }

              // The folder gives way (elided in the middle) before the name does.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(implicitWidth, rowColumn.width * 0.35,
                                            rowColumn.width - x - whenText.implicitWidth - Style.space(12)))
                text: sessionRow.s.cwd ? Format.folder(sessionRow.s.cwd, root.home) : ""
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: root.pal.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Text {
              id: whenText
              anchors.right: pinButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              // Stop takes this spot while the row is hovered.
              opacity: stopButton.visible ? 0 : 1
              text: sessionRow.s.waiting ? "needs you · " + Format.clock(root.now, sessionRow.s.turnStart)
                : sessionRow.s.busy ? (sessionRow.s.thinking ? "thinking · " : "") + Format.clock(root.now, sessionRow.s.turnStart)
                  + (sessionRow.s.turnTokens ? " · " + Format.tokens(sessionRow.s.turnTokens, " tok") : "")
                : "idle " + Format.ago(root.now, sessionRow.s.since)
              textFormat: Text.PlainText
              color: sessionRow.s.waiting ? root.pal.needsYouText : root.pal.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: sessionRow.s.waiting
            }

            Pill {
              id: stopButton
              anchors.right: pinButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              visible: sessionRow.stoppable && (rowMouse.containsMouse || hovered)
              pal: root.pal
              fontFamily: root.fontFamily
              compact: true
              label: "■ Stop"
              onClicked: root.stopRequested(sessionRow.s)
            }

            // Pin: filled when pinned, else shown on hover. It holds the right
            // edge so it stays put while Stop and the time swap beside it.
            Pill {
              id: pinButton
              readonly property bool starred: root.starredIds.indexOf(sessionRow.s.id) >= 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              opacity: starred || rowMouse.containsMouse || hovered ? 1 : 0
              enabled: opacity > 0
              pal: root.pal
              fontFamily: root.fontFamily
              compact: true
              kind: "quiet"
              label: starred ? "★" : "☆"
              tooltip: starred ? "Unpin" : "Pin"
              onClicked: root.starRequested(sessionRow.s)
            }

            // Beside Stop: why the sleep sweep hasn't stopped it.
            Text {
              anchors.right: stopButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              visible: stopButton.visible && text !== ""
              text: stopButton.visible ? root.awakeLine(sessionRow.s) : ""
              textFormat: Text.PlainText
              color: root.pal.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            readonly property string line: sessionRow.s.waiting
              ? "⚠ " + (sessionRow.s.waitingFor ? sessionRow.s.waitingFor.charAt(0).toUpperCase() + sessionRow.s.waitingFor.slice(1) : "Needs input")
                + (sessionRow.s.activity ? " · " + sessionRow.s.activity : "")
              : sessionRow.s.busy ? (sessionRow.s.thinking ? "Thinking…" : sessionRow.s.activity)
              : (sessionRow.s.reply ? "↳ " + sessionRow.s.reply : sessionRow.s.prompt)
            visible: line !== ""
            width: parent.width
            text: line
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: sessionRow.lively ? 1 : 2
            wrapMode: Text.Wrap
            color: sessionRow.s.waiting ? root.pal.needsYouText : sessionRow.s.busy ? root.pal.fg : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.italic: sessionRow.s.busy
          }

          // Subagents and background shells it has running alongside.
          Text {
            visible: text !== ""
            text: root.childSummary(sessionRow.s.children || [], sessionRow.s.queued)
            textFormat: Text.PlainText
            color: root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }
  }

  // Click to list every idle session; click again to go back to the first few.
  Text {
    visible: root.hiddenIdle > 0 || (root.idleExpanded && root.idleCount > root.idleLimit)
    leftPadding: Style.space(14)
    topPadding: Style.space(6)
    text: root.idleExpanded ? "show fewer idle" : "+ " + root.hiddenIdle + " more idle"
    textFormat: Text.PlainText
    color: idleMouse.containsMouse ? root.pal.fg : root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    Behavior on color { ColorAnimation { duration: 120 } }

    MouseArea {
      id: idleMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.idleToggled()
    }
  }
}
