import QtQuick
import qs.Commons
import "Calendar.js" as Calendar
import "Icons.js" as Icons

// The Today mode of Home's main card: a month grid with ISO week numbers
// (‹ › or the scroll wheel step the month, a click on the title comes back to
// this one) beside the weather: now, and the next three days. The weather is
// fetched by BarWidget (wttr.in) and parsed by Weather.js; null: not yet.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property double now: Date.now()
  // Weather.js parse(): {temp, feels, desc, icon, place, days}
  property var weather: null

  readonly property var today: new Date(now)
  readonly property string todayKey: Calendar.dateKey(today.getFullYear(), today.getMonth(), today.getDate())
  property int year: today.getFullYear()
  property int month: today.getMonth()
  readonly property var grid: Calendar.monthGrid(year, month, todayKey)
  // The weather keeps its width; the month takes the rest, never narrower than 8 × 25.
  readonly property real weatherW: Style.space(210)
  readonly property real calW: Math.max(Style.space(25) * 8, width - weatherW - Style.space(36) - 1)
  readonly property real cell: calW / 8
  readonly property real rowH: Style.space(19)

  implicitHeight: Style.space(22) + Style.space(6) + Style.space(14) + rowH * 6

  function step(delta) {
    var m = Calendar.stepMonth(year, month, delta)
    year = m.year
    month = m.month
  }

  function reset() {
    year = today.getFullYear()
    month = today.getMonth()
  }

  // Back on this month when the card comes back, and when the day rolls over.
  onVisibleChanged: if (visible) reset()
  onTodayKeyChanged: reset()

  component Label: Text {
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ---- The month
  Item {
    id: calendar
    width: root.calW
    height: parent.height

    Item {
      id: head
      width: parent.width
      height: Style.space(22)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Calendar.months[root.month] + (root.year !== root.today.getFullYear() ? " " + root.year : "")
        textFormat: Text.PlainText
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.reset()
        }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Repeater {
          model: [{ icon: Icons.back, d: -1 }, { icon: Icons.forward, d: 1 }]

          Rectangle {
            required property var modelData
            width: Style.space(22)
            height: Style.space(22)
            radius: height / 2
            color: root.pal.alpha(root.pal.fg, stepMouse.containsMouse ? 0.08 : 0)

            Icon {
              anchors.centerIn: parent
              d: parent.modelData.icon
              size: Style.space(12)
              color: root.pal.muted
            }

            MouseArea {
              id: stepMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.step(parent.modelData.d)
            }
          }
        }
      }
    }

    Column {
      y: head.height + Style.space(6)
      width: parent.width

      // Mon … Sun, with W over the week-number column.
      Row {
        height: Style.space(14)
        Label { width: root.cell; text: "W"; opacity: 0.55; horizontalAlignment: Text.AlignHCenter }
        Repeater {
          model: ["M", "T", "W", "T", "F", "S", "S"]
          Label {
            required property string modelData
            width: root.cell
            text: modelData
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }

      Repeater {
        model: root.grid

        Row {
          required property var modelData
          height: root.rowH

          Label {
            width: root.cell
            height: parent.height
            text: parent.modelData.week
            opacity: 0.55
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }

          Repeater {
            model: parent.modelData.days

            Item {
              required property var modelData
              width: root.cell
              height: root.rowH

              Rectangle {
                anchors.centerIn: parent
                width: Style.space(21)
                height: Style.space(17)
                radius: height / 2
                color: parent.modelData.today ? root.pal.crab : "transparent"
              }

              Text {
                anchors.centerIn: parent
                text: parent.modelData.day
                textFormat: Text.PlainText
                color: parent.modelData.today ? root.pal.card
                  : parent.modelData.inMonth ? (parent.modelData.weekend ? root.pal.muted : root.pal.strong)
                  : root.pal.alpha(root.pal.muted, 0.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: parent.modelData.today
              }
            }
          }
        }
      }
    }

    // The wheel steps the month, a notch at a time.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      onWheel: function(w) { if (w.angleDelta.y !== 0) root.step(w.angleDelta.y < 0 ? 1 : -1) }
    }
  }

  Rectangle {
    id: divider
    x: calendar.width + Style.space(18)
    width: 1
    height: parent.height
    color: root.pal.hairline
  }

  // ---- The weather
  Item {
    id: weatherBox
    x: divider.x + Style.space(18)
    width: parent.width - x
    height: parent.height

    Column {
      visible: !!root.weather
      width: parent.width
      spacing: Style.space(12)

      Row {
        spacing: Style.space(12)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.weather ? root.weather.icon : ""
          textFormat: Text.PlainText
          color: root.pal.crab
          font.pixelSize: Style.font.heading * 2
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: root.weather ? root.weather.temp : ""
            textFormat: Text.PlainText
            color: root.pal.strong
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading + Style.space(6)
            font.bold: true
          }
          Label {
            width: weatherBox.width - Style.space(60)
            text: root.weather ? root.weather.desc + (root.weather.feels ? " · feels " + root.weather.feels : "") : ""
          }
        }
      }

      Label {
        width: parent.width
        text: root.weather ? root.weather.place : ""
      }

      Repeater {
        model: root.weather ? root.weather.days : []

        Row {
          required property var modelData
          spacing: Style.space(10)

          Label { width: Style.space(42); text: parent.modelData.name; color: root.pal.fg }
          Text {
            width: Style.space(20)
            text: parent.modelData.icon
            textFormat: Text.PlainText
            color: root.pal.muted
            font.pixelSize: Style.font.body
          }
          Label { text: parent.modelData.hi + "  " + parent.modelData.lo }
        }
      }
    }

    Label {
      visible: !root.weather
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      text: "Fetching the weather…"
    }
  }
}
