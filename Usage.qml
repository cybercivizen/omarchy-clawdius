import QtQuick
import qs.Commons

// Claude usage, folded in from the old agents panel: plan, the 5-hour and
// weekly limits (with a pace tick for where an even burn would be), today's
// tokens, the per-model split, and the last week. On a wide card the limits
// and the activity sit side by side, so no bar runs the whole width.
//
// `record` is the claude.json that omarchy-agent-usage-claude writes.
Column {
  id: root

  property var record: null
  property double now: Date.now()
  property color fg: Color.foreground
  property color mutedFg: Qt.darker(fg, 1.45)
  property color accent: "#D97757"
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  readonly property color track: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property var limits: (record && record.limits) ? record.limits.filter(function(l) { return Number(l.percent) >= 0 }) : []
  readonly property var models: modelRows(record ? record.todayTokensByModel : null)
  readonly property var days: (record && record.recentDays) ? record.recentDays.slice(-7) : []
  readonly property real dayMax: Math.max.apply(null, [1].concat(days.map(function(d) { return Number(d.messageCount) || 0 })))
  readonly property double updatedMs: record && record.updatedAt ? new Date(record.updatedAt).getTime() : 0

  readonly property bool wide: width >= Style.space(520)
  readonly property real gutter: Style.space(28)
  readonly property real colWidth: wide ? (width - gutter) / 2 : width

  spacing: Style.space(8)
  visible: !!record

  function tokens(n) {
    n = Number(n) || 0
    if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3) return Math.round(n / 1e3) + "K"
    return String(n)
  }

  // "claude-opus-5-5" -> "Opus 5.5"
  function modelName(id) {
    var parts = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "").split("-")
    var name = parts.shift() || id
    name = name.charAt(0).toUpperCase() + name.slice(1)
    return parts.length ? name + " " + parts.join(".") : name
  }

  function modelRows(map) {
    var out = []
    for (var id in (map || {})) out.push({ name: modelName(id), tokens: Number(map[id]) || 0 })
    out.sort(function(a, b) { return b.tokens - a.tokens })
    return out
  }

  function duration(ms) {
    if (!(ms > 0)) return "now"
    var m = Math.floor(ms / 60000), h = Math.floor(m / 60), d = Math.floor(h / 24)
    if (d > 0) return d + "d " + (h % 24) + "h"
    if (h > 0) return h + "h " + (m % 60) + "m"
    return Math.max(1, m) + "m"
  }

  // Window length from the label, for the pace tick.
  function windowMs(label) {
    var s = String(label || "").toLowerCase()
    var hours = s.match(/(\d+)\s*-?\s*h/), days = s.match(/(\d+)\s*-?\s*d/)
    if (hours) return Number(hours[1]) * 3600000
    if (days) return Number(days[1]) * 86400000
    if (s.indexOf("week") >= 0) return 7 * 86400000
    return 0
  }

  function shortLabel(label) {
    var s = String(label || "")
    var m = s.match(/^(.*?)\s*\((.*)\)\s*$/)
    return m ? m[1] + " · " + m[2].replace(/-?hour/, "h").replace(/-?day/, "d") : s
  }

  function dayInitial(date, isToday) {
    if (isToday) return "today"
    var d = new Date(date + "T12:00:00")
    return isFinite(d.getTime()) ? Qt.locale("en_US").dayName(d.getDay(), Locale.ShortFormat) : ""
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.mutedFg
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ---- Header
  Item {
    width: parent.width
    height: header.implicitHeight

    Label {
      id: header
      text: "USAGE" + (root.record && root.record.tierLabel ? "  ·  " + root.record.tierLabel : "")
      font.bold: true
      font.letterSpacing: 0.6
    }

    Label {
      anchors.right: parent.right
      anchors.baseline: header.baseline
      text: root.record && root.record.usageStatusText ? root.record.usageStatusText
        : root.updatedMs ? "updated " + root.duration(root.now - root.updatedMs) + " ago" : ""
    }
  }

  Grid {
    width: parent.width
    columns: root.wide ? 2 : 1
    columnSpacing: root.gutter
    rowSpacing: Style.space(12)

    // ---- Limits
    Column {
      width: root.colWidth
      spacing: Style.space(10)

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
          width: parent.width
          spacing: Style.space(3)

          Item {
            width: parent.width
            height: limitName.implicitHeight

            Text {
              id: limitName
              text: root.shortLabel(limit.modelData.label)
              textFormat: Text.PlainText
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              anchors.right: parent.right
              anchors.baseline: limitName.baseline
              text: Math.round(limit.value * 100) + "%" + (limit.resetIn > 0 ? "  ·  resets in " + root.duration(limit.resetIn) : "")
              textFormat: Text.PlainText
              color: limit.alarming ? root.urgent : root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            width: parent.width
            height: Style.space(5)

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: root.track
            }

            Rectangle {
              height: parent.height
              width: Math.max(height, parent.width * limit.value)
              radius: height / 2
              color: limit.alarming ? root.urgent : (limit.pace >= 0 && limit.value > limit.pace ? root.accent : root.fg)
              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }

            // Pace: where usage would sit if spread evenly over the window.
            Rectangle {
              visible: limit.pace >= 0
              x: Math.round(parent.width * limit.pace) - width / 2
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(2, Style.space(2))
              height: parent.height + Style.space(4)
              radius: width / 2
              color: root.mutedFg
            }
          }
        }
      }

      Label {
        visible: root.limits.length === 0 && !!(root.record && root.record.authHelpText)
        width: parent.width
        wrapMode: Text.Wrap
        text: root.record ? root.record.authHelpText : ""
      }
    }

    // ---- Today
    Column {
      width: root.colWidth
      spacing: Style.space(6)

      Text {
        width: parent.width
        text: "Today  " + root.tokens(root.record ? root.record.todayTotalTokens : 0) + " tokens  ·  "
          + (root.record ? root.record.todayPrompts || 0 : 0) + " prompts  ·  "
          + (root.record ? root.record.todaySessions || 0 : 0) + " sessions"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        model: root.models

        Item {
          required property var modelData
          width: parent.width
          height: modelLabel.implicitHeight

          Label {
            id: modelLabel
            width: Style.space(80)
            text: modelData.name
            elide: Text.ElideRight
          }

          Rectangle {
            anchors.left: modelLabel.right
            anchors.right: modelValue.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(4)
            radius: height / 2
            color: root.track

            Rectangle {
              height: parent.height
              radius: parent.radius
              width: Math.max(height, parent.width * (modelData.tokens / Math.max(1, root.models[0].tokens)))
              color: root.accent
              opacity: 0.85
            }
          }

          Label {
            id: modelValue
            anchors.right: parent.right
            width: Style.space(40)
            horizontalAlignment: Text.AlignRight
            text: root.tokens(modelData.tokens)
          }
        }
      }

      // ---- Last 7 days
      Row {
        visible: root.days.length > 1
        width: parent.width
        height: Style.space(root.wide ? 44 : 34)
        spacing: Style.space(4)
        topPadding: Style.space(4)

        Repeater {
          model: root.days

          Column {
            id: day
            required property var modelData
            required property int index
            readonly property bool isToday: index === root.days.length - 1
            readonly property real amount: Number(modelData.messageCount) || 0
            width: (parent.width - Style.space(4) * (root.days.length - 1)) / root.days.length
            spacing: Style.space(2)

            Item {
              width: parent.width
              height: Style.space(root.wide ? 26 : 18)

              Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.6
                height: day.amount > 0 ? Math.max(2, parent.height * day.amount / root.dayMax) : 1
                radius: Style.space(1)
                color: day.isToday ? root.accent : (day.amount > 0 ? root.fg : root.track)
                opacity: day.isToday || day.amount === 0 ? 1 : 0.55
              }
            }

            Label {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: root.dayInitial(day.modelData.date, day.isToday)
              color: day.isToday ? root.fg : root.mutedFg
            }
          }
        }
      }
    }
  }
}
