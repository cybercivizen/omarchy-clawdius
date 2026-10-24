import QtQuick
import qs.Commons
import "Icons.js" as Icons
import "Timers.js" as Timers

// The Timer mode of Home's corner card: what's counting down, and a small
// setter for the next one. One list holds both kinds (a timer is "in 10
// min", an alarm is "at 14:30"); the engine that rings them lives in
// BarWidget, this only asks for them.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property var timers: []
  property double now: Date.now()

  signal added(string kind, string label, double at, double len)
  signal cancelled(string id)

  // The setter shows when nothing runs, or when "New" was pressed.
  property bool composing: false
  readonly property bool setting: composing || timers.length === 0
  property string kind: "timer"
  property int minutes: 10
  property int alarmAt: Timers.defaultAlarm(Date.now())

  readonly property var shown: timers.slice().sort(function(a, b) { return a.at - b.at }).slice(0, 2)

  implicitHeight: setting ? setter.implicitHeight : list.implicitHeight

  function start() {
    var t = Date.now()
    if (kind === "alarm") {
      var at = Timers.nextClock(alarmAt, t)
      added("alarm", "Alarm " + Timers.clock(alarmAt), at, at - t)
    } else {
      var len = minutes * 60000
      added("timer", Timers.span(minutes), t + len, len)
    }
    composing = false
  }

  // ---- The setter
  Column {
    id: setter
    visible: root.setting
    width: parent.width
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: Style.space(24)

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(12)

        Repeater {
          model: Timers.kinds

          Text {
            required property var modelData
            text: modelData.name
            textFormat: Text.PlainText
            color: root.kind === modelData.id ? root.pal.strong : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: root.kind === modelData.id

            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(3)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.kind = parent.modelData.id
            }
          }
        }
      }

      Text {
        visible: root.timers.length > 0
        anchors.right: startPill.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        text: "Back"
        textFormat: Text.PlainText
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(3)
          cursorShape: Qt.PointingHandCursor
          onClicked: root.composing = false
        }
      }

      Pill {
        id: startPill
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        pal: root.pal
        dense: true
        fontFamily: root.fontFamily
        kind: "primary"
        icon: root.kind === "timer" ? Icons.timer : Icons.bell
        label: Timers.kinds[root.kind === "alarm" ? 1 : 0].verb
        onClicked: root.start()
      }
    }

    Item {
      width: parent.width
      height: Style.space(30)

      Pill {
        pal: root.pal
        compact: true
        iconOnly: true
        icon: Icons.minus
        onClicked: root.kind === "alarm" ? root.alarmAt = (root.alarmAt + 1440 - 15) % 1440 : root.minutes = Timers.step(root.minutes, -1)
      }

      Text {
        anchors.centerIn: parent
        text: root.kind === "alarm" ? Timers.clock(root.alarmAt) : Timers.span(root.minutes)
        textFormat: Text.PlainText
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }

      Pill {
        anchors.right: parent.right
        pal: root.pal
        compact: true
        iconOnly: true
        icon: Icons.plus
        onClicked: root.kind === "alarm" ? root.alarmAt = (root.alarmAt + 15) % 1440 : root.minutes = Timers.step(root.minutes, 1)
      }
    }

    // Presets for a timer, the wait for an alarm.
    Item {
      width: parent.width
      height: Style.space(26)

      Row {
        visible: root.kind === "timer"
        anchors.centerIn: parent
        spacing: Style.space(6)

        Repeater {
          model: Timers.presets

          Rectangle {
            required property int modelData
            width: presetText.implicitWidth + Style.space(18)
            height: Style.space(24)
            radius: pal.pill(height)
            color: root.minutes === modelData ? root.pal.alpha(root.pal.fg, 0.14) : root.pal.alpha(root.pal.fg, presetMouse.containsMouse ? 0.08 : 0.04)

            Text {
              id: presetText
              anchors.centerIn: parent
              text: parent.modelData + "m"
              textFormat: Text.PlainText
              color: root.minutes === parent.modelData ? root.pal.strong : root.pal.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            MouseArea {
              id: presetMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.minutes = parent.modelData
            }
          }
        }
      }

      Text {
        visible: root.kind === "alarm"
        anchors.centerIn: parent
        text: {
          var wait = Timers.nextClock(root.alarmAt, root.now) - root.now
          return (wait > 86400000 - 60000 ? "tomorrow · " : "") + "in " + Timers.left(wait + 59000)
        }
        textFormat: Text.PlainText
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

  }

  // ---- What's running
  Column {
    id: list
    visible: !root.setting
    width: parent.width
    spacing: Style.space(6)

    Repeater {
      model: root.shown

      Item {
        id: entry
        required property var modelData
        readonly property double remaining: modelData.at - root.now
        width: list.width
        height: Style.space(32)

        Icon {
          id: entryIcon
          anchors.verticalCenter: parent.verticalCenter
          d: entry.modelData.kind === "timer" ? Icons.timer : Icons.bell
          size: Style.space(15)
          color: root.pal.muted
        }

        Column {
          x: entryIcon.width + Style.space(10)
          width: parent.width - x - entryTime.width - closeButton.width - Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)

          Text {
            width: parent.width
            text: entry.modelData.label
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.pal.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // A thin bar emptying as the time runs down.
          Rectangle {
            width: parent.width
            height: Style.space(3)
            radius: pal.pill(height)
            color: root.pal.alpha(root.pal.fg, 0.12)

            Rectangle {
              height: parent.height
              radius: pal.pill(height)
              width: parent.width * Math.max(0, Math.min(1, entry.remaining / Math.max(1, entry.modelData.len)))
              color: entry.remaining < 60000 ? root.pal.crab : root.pal.fg
            }
          }
        }

        Text {
          id: entryTime
          anchors.right: closeButton.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: Timers.left(entry.remaining)
          textFormat: Text.PlainText
          color: entry.remaining < 60000 ? root.pal.crab : root.pal.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Pill {
          id: closeButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          pal: root.pal
          compact: true
          kind: "quiet"
          iconOnly: true
          icon: Icons.cross
          width: Style.space(26)
          height: width
          onClicked: root.cancelled(entry.modelData.id)
        }
      }
    }

    Pill {
      visible: root.timers.length < 6
      width: parent.width
      pal: root.pal
      compact: true
      icon: Icons.plus
      label: root.timers.length > root.shown.length ? "New · +" + (root.timers.length - root.shown.length) + " later" : "New"
      onClicked: root.composing = true
    }
  }
}
