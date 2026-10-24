import QtQuick
import qs.Commons
import "Icons.js" as Icons

// The Limits mode of Home's corner card (Corner.qml): a glance at the Claude
// limits, the 5-hour window and the week, each with a tick where an even
// burn would be. Orange when ahead of that pace, red at 90%. Clicking it
// opens the full Stats.
Item {
  id: root

  property QtObject pal
  property var record: null
  property double now: Date.now()
  property string fontFamily: Style.font.family

  signal activated()

  readonly property var limits: (record && record.limits) ? record.limits.filter(function(l) { return Number(l.percent) >= 0 }).slice(0, 2) : []

  function duration(ms) {
    if (!(ms > 0)) return "now"
    var m = Math.floor(ms / 60000), h = Math.floor(m / 60), d = Math.floor(h / 24)
    if (d > 0) return d + "d " + (h % 24) + "h"
    if (h > 0) return h + "h " + (m % 60) + "m"
    return Math.max(1, m) + "m"
  }

  function windowMs(label) {
    var s = String(label || "").toLowerCase()
    var hours = s.match(/(\d+)\s*-?\s*h/), days = s.match(/(\d+)\s*-?\s*d/)
    if (hours) return Number(hours[1]) * 3600000
    if (days) return Number(days[1]) * 86400000
    if (s.indexOf("week") >= 0) return 7 * 86400000
    return 0
  }

  // "Current session (5-hour)" → "5-hour"; "Current week (all models)" → "Week".
  function name(label) {
    var s = String(label || "")
    if (/5-?\s*h|session/i.test(s)) return "5-hour"
    if (/week|7-?\s*d/i.test(s)) return /opus|sonnet/i.test(s) ? "Week · " + s.match(/opus|sonnet/i)[0] : "Week"
    return s.replace(/\s*\(.*\)\s*$/, "")
  }

  // Resets within a day: "in 1h 40m"; further out: the day and time.
  function resets(at) {
    var t = new Date(at).getTime()
    if (!isFinite(t)) return ""
    if (t - root.now < 86400000) return "resets in " + duration(t - root.now)
    return "resets " + Qt.formatDateTime(new Date(t), "ddd HH:mm")
  }

  implicitHeight: column.implicitHeight

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Style.space(6)
    radius: pal.rad(Style.space(14))
    color: root.pal ? root.pal.alpha(root.pal.fg, mouse.containsMouse ? 0.04 : 0) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(14)

    Repeater {
      model: root.limits

      Column {
        id: limit
        required property var modelData
        readonly property real value: Math.max(0, Math.min(1, Number(modelData.percent)))
        readonly property bool alarming: value >= 0.9
        readonly property double resetIn: modelData.resetsAt ? new Date(modelData.resetsAt).getTime() - root.now : -1
        readonly property double span: root.windowMs(modelData.label)
        readonly property real pace: span > 0 && resetIn > 0 ? Math.max(0, Math.min(1, 1 - resetIn / span)) : -1
        readonly property bool ahead: pace >= 0 && value > pace
        width: parent.width
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: limitName.implicitHeight

          Text {
            id: limitName
            text: root.name(limit.modelData.label)
            textFormat: Text.PlainText
            color: root.pal.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            anchors.right: parent.right
            text: Math.round(limit.value * 100) + "%"
            textFormat: Text.PlainText
            color: limit.alarming ? root.pal.failed : root.pal.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: limit.alarming
          }
        }

        Item {
          width: parent.width
          height: Style.space(4)

          Rectangle {
            anchors.fill: parent
            radius: pal.pill(height)
            color: root.pal.alpha(root.pal.fg, 0.14)
          }

          Rectangle {
            height: parent.height
            width: Math.max(height, parent.width * limit.value)
            radius: pal.pill(height)
            color: limit.alarming ? root.pal.failed : limit.ahead ? root.pal.crab : root.pal.fg
            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          }

          // Pace: where usage would sit if spread evenly over the window.
          Rectangle {
            visible: limit.pace >= 0
            x: Math.round(parent.width * limit.pace)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(1.5, Style.spaceReal(1.5))
            height: Style.space(8)
            color: root.pal.alpha(root.pal.fg, 0.6)
          }
        }

        Text {
          width: parent.width
          text: (limit.alarming ? "nearly out · " : limit.ahead ? "ahead of pace · " : "")
            + (limit.modelData.resetsAt ? root.resets(limit.modelData.resetsAt) : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      visible: root.limits.length === 0
      width: parent.width
      text: root.record && root.record.authHelpText ? root.record.authHelpText : "No usage data yet."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
