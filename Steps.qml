import QtQuick
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// A session's short step list. Claude's own plan when it wrote one (the
// feed's `tasks`: done dim with ✓, the current one bright with an orange
// dot, what's next dim in an empty ring); otherwise the last few tool calls
// from the transcript (`actions`: ✓ done, ✗ failed, ■ stopped when the turn
// ended before its result), each in the call's own words.
//
// While the session is busy the last row is always what it's doing right
// now, lit up with a clock: the running call with the command or path under
// it, or "Thinking…" between calls (tools mostly finish within the feed's
// one-second poll, so a list of only past calls would show nothing but
// ticks). Under the list, Claude's latest words this turn, in quotes.
// With `foldThinking` (Home), the gap between calls takes no row of its own:
// the newest step (the plan's current one) gets the spinner and a "thinking"
// clock instead, so the rows stay what it has actually done.
Column {
  id: root

  property QtObject pal
  property var session: null
  property int limit: 3
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.subtitle
  property bool animate: true
  property double now: Date.now()
  // The done ✓ as a filled green dot (the detail view) rather than a plain tick.
  property bool filledDone: false
  property bool showNote: true
  // Lines of the running call's command shown under it.
  property int detailLines: 1
  property bool foldThinking: false

  readonly property var s: session || ({})
  readonly property bool busy: !!s.busy
  readonly property var tasks: s.tasks || []
  readonly property bool isPlan: tasks.length > 0
  readonly property var actions: s.actions || []
  readonly property var runningAction: {
    for (var i = actions.length - 1; i >= 0; i--) if (actions[i].status === "running") return actions[i]
    return null
  }
  // What it's doing right now: the call that's out, else its own move.
  readonly property var thinkingRow: ({ text: s.thinking ? "Thinking it over…" : "Thinking…", detail: "", at: s.phaseAt || 0, state: "running", now: true })
  readonly property bool folding: foldThinking && busy && !runningAction
  readonly property var current: !busy || folding ? null
    : runningAction ? { text: runningAction.text, detail: runningAction.detail || "", at: runningAction.at || s.phaseAt || 0, state: "running", now: true }
    : thinkingRow

  readonly property var history: isPlan ? planWindow(tasks, current ? limit - 1 : limit)
    : actions.filter(function(a) { return a !== runningAction })
             .slice(-(current ? limit - 1 : limit))
             .map(function(a) { return { text: a.text, detail: a.detail || "", state: a.status, now: false } })
  readonly property var items: current ? history.concat([current]) : folding ? foldIn(history) : history

  // Folding: the plan's current step, else the newest call, carries the
  // thinking clock; with neither, a Thinking row as usual.
  function foldIn(list) {
    var at = -1
    for (var i = 0; i < list.length; i++) if (list[i].state === "current") at = i
    if (at < 0 && !isPlan) at = list.length - 1
    if (at < 0) return list.slice(Math.max(0, list.length - limit + 1)).concat([thinkingRow])
    return list.map(function(x, i) {
      return i !== at ? x : { text: x.text, detail: "", state: x.state, now: false, thinking: true, at: s.phaseAt || 0 }
    })
  }
  // Claude's latest words, while they're about this turn's work.
  readonly property string note: showNote && busy ? String(s.note || "") : ""

  // The plan around where it's at: the last done step, the current one and
  // what follows, `count` in all. Its running step is the plan's; the live
  // row under it says what that step is doing.
  function planWindow(list, count) {
    var at = 0
    while (at < list.length && list[at].status === "completed") at++
    var start = Math.max(0, Math.min(at - 1, list.length - count))
    return list.slice(start, start + count).map(function(t) {
      return { text: t.text, detail: "", now: false,
               state: t.status === "completed" ? "done" : t.status === "in_progress" ? "current" : "pending" }
    })
  }

  spacing: pal ? pal.sp(8) : Style.space(8)

  Repeater {
    // Only while shown (animate: the card is up): each feed update rebuilds every row.
    model: root.animate ? root.items : []

    Item {
      id: step
      required property var modelData
      readonly property string state: modelData.state
      readonly property bool live: modelData.now === true
      readonly property bool thinkingHere: modelData.thinking === true
      // The mark drawn: the spinner while it's thinking after this step.
      readonly property string mark: thinkingHere ? "running" : state
      readonly property bool hasDetail: live && modelData.detail !== ""
      readonly property real livePad: Style.space(root.pal && root.pal.dense ? 4 : 8)
      width: root.width
      height: row.implicitHeight + (live ? livePad * 2 : 0)

      // The live row sits on a faint orange wash.
      Rectangle {
        visible: step.live
        anchors.fill: parent
        anchors.leftMargin: -Style.space(8)
        radius: pal.rad(Style.space(10))
        color: root.pal ? root.pal.alpha(root.pal.crab, root.pal.light ? 0.08 : 0.10) : "transparent"
        border.width: 1
        border.color: root.pal ? root.pal.alpha(root.pal.crab, 0.22) : "transparent"
      }

      Row {
        id: row
        y: step.live ? step.livePad : 0
        width: parent.width - (step.live ? Style.space(8) : 0)
        spacing: Style.space(11)

        Item {
          id: mark
          width: Style.space(15)
          height: Math.max(width, label.implicitHeight)

          // ✓ done: a plain tick, or a filled green dot.
          Rectangle {
            visible: step.mark === "done" && root.filledDone
            anchors.centerIn: parent
            width: Style.space(15)
            height: width
            radius: width / 2
            color: root.pal ? root.pal.done : "green"
            Icon {
              anchors.centerIn: parent
              d: Icons.check
              size: Style.space(11)
              stroke: 3
              color: "white"
            }
          }

          Icon {
            visible: (step.mark === "done" && !root.filledDone) || step.mark === "failed"
            anchors.centerIn: parent
            d: step.state === "failed" ? Icons.cross : Icons.check
            size: Style.space(15)
            color: !root.pal ? "white" : step.state === "failed" ? root.pal.failed : root.pal.dim
          }

          // Running: an orange arc going round a faint ring.
          Item {
            visible: step.mark === "running"
            anchors.centerIn: parent
            width: Style.space(13)
            height: width

            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "transparent"
              border.width: 2
              border.color: root.pal ? root.pal.alpha(root.pal.fg, 0.2) : "gray"
            }

            Icon {
              id: arc
              anchors.centerIn: parent
              d: "M12 2a10 10 0 0 1 10 10"
              size: parent.width
              stroke: 2 * 24 / parent.width
              color: root.pal ? root.pal.crab : "orange"
              Spin { target: arc; running: step.mark === "running" && root.animate && root.visible }
            }
          }

          // The plan's current step: a filled orange dot (the live row under
          // it carries the spinner).
          Rectangle {
            visible: step.mark === "current"
            anchors.centerIn: parent
            width: Style.space(9)
            height: width
            radius: width / 2
            color: root.pal ? root.pal.crab : "orange"
          }

          // Stopped (interrupted before its result): a small square.
          Rectangle {
            visible: step.mark === "stopped"
            anchors.centerIn: parent
            width: Style.space(8)
            height: width
            radius: Style.space(2)
            color: root.pal ? root.pal.dim : "gray"
          }

          // Pending: an empty ring.
          Rectangle {
            visible: step.mark === "pending"
            anchors.centerIn: parent
            width: Style.space(11)
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 1.5
            border.color: root.pal ? root.pal.dim : "gray"
          }
        }

        Column {
          width: row.width - mark.width - row.spacing
          spacing: Style.space(3)

          Item {
            width: parent.width
            height: label.implicitHeight

            Text {
              id: label
              width: parent.width - (clock.visible ? clock.implicitWidth + Style.space(8) : 0)
              text: step.modelData.text
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: !root.pal ? "white"
                : step.live || step.thinkingHere || step.state === "current" ? root.pal.strong
                : step.state === "failed" ? root.pal.fg
                : step.state === "pending" || step.state === "stopped" ? root.pal.muted
                : root.pal.dim
              font.family: root.fontFamily
              font.pixelSize: root.fontSize
              font.bold: step.live || step.state === "current"
            }

            // How long it's been at it.
            Text {
              id: clock
              visible: (step.live || step.thinkingHere) && step.modelData.at > 0
              anchors.right: parent.right
              anchors.verticalCenter: label.verticalCenter
              text: (step.thinkingHere ? (root.s.thinking ? "thinking it over " : "thinking ") : "") + Format.clock(root.now, step.modelData.at)
              textFormat: Text.PlainText
              color: root.pal ? root.pal.crab : "orange"
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // The call itself: the command, file or pattern.
          Text {
            visible: step.hasDetail
            width: parent.width
            text: step.modelData.detail
            textFormat: Text.PlainText
            wrapMode: root.detailLines > 1 ? Text.WrapAnywhere : Text.NoWrap
            maximumLineCount: root.detailLines
            elide: Text.ElideRight
            color: root.pal ? root.pal.muted : "gray"
            font.family: "monospace"
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // "Now I'll check the README." — what Claude last said it'd do.
  Item {
    visible: root.note !== ""
    width: root.width
    height: noteText.implicitHeight + Style.space(2)

    Rectangle {
      width: Style.space(2)
      height: parent.height
      radius: width / 2
      color: root.pal ? root.pal.alpha(root.pal.fg, 0.18) : "gray"
    }

    Text {
      id: noteText
      x: Style.space(12)
      width: parent.width - x
      text: "“" + root.note + "”"
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: root.pal ? root.pal.muted : "gray"
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.italic: true
    }
  }
}
