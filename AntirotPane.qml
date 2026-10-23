import QtQuick
import qs.Commons
import "Icons.js" as Icons

// The Anti-rot mode of Home's corner card: today against the quota, the one
// button that moves the current challenge on, and two steppers (‹ ›) instead
// of lists: one over the languages (level, progress, usual solve time), one
// over what's been done. It is how to ask for the next challenge while
// Claude is working and the left side is busy. The actions go to BarWidget
// as the challenge card's do.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // antirot.json, as antirot.py writes it.
  property var antirot: null
  // The antirot.py action running: "" | start | check | next | …
  property string busy: ""
  // The steppers' positions; langPick -1 follows today's language.
  property int langPick: -1
  property int doneAt: 0

  // start | open | check | next | settings
  signal challenge(string action)

  readonly property var rep: antirot ? antirot.today : null
  readonly property var info: antirot && antirot.info ? antirot.info : ({})
  readonly property var langs: antirot && antirot.langs ? antirot.langs : ({})
  readonly property var langsOn: Object.keys(langs).filter(function(l) { return langs[l].on }).sort()
  readonly property int langAt: langsOn.length ? (langPick >= 0 ? langPick % langsOn.length : Math.max(0, langsOn.indexOf(rep ? rep.lang : ""))) : 0
  readonly property string lang: langsOn.length ? langsOn[langAt] : ""
  readonly property var byLang: antirot && antirot.stats ? antirot.stats.byLang : ({})
  readonly property int redos: antirot && antirot.stats ? antirot.stats.redos : 0
  readonly property var recent: antirot && antirot.stats ? antirot.stats.recent : []
  readonly property int total: antirot && antirot.stats ? antirot.stats.total : 0
  readonly property int doneIdx: Math.min(doneAt, Math.max(0, recent.length - 1))
  readonly property int perDay: antirot ? antirot.perDay || 1 : 1
  readonly property int doneToday: antirot ? antirot.doneToday || 0 : 0
  readonly property int streak: antirot ? antirot.streakNow || 0 : 0
  readonly property int passesToLevel: antirot ? antirot.passesToLevel || 2 : 2
  readonly property bool inProgress: !!rep && !!rep.startedAt && !rep.passedAt
  readonly property bool passed: !!rep && !!rep.passedAt

  implicitHeight: body.implicitHeight

  function langName(l) { return info[l] ? info[l].name : l }

  // " · ~14m (was 22m)": the usual solve time lately, and the five before.
  function pace(l) {
    var m = byLang[l]
    if (!m || !m.median) return ""
    return "~" + Math.max(1, Math.round(m.median / 60)) + "m" + (m.before ? " (was " + Math.max(1, Math.round(m.before / 60)) + "m)" : "")
  }

  function dayName(iso) {
    var d = new Date()
    var today = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
    if (iso === today) return "today"
    d.setDate(d.getDate() - 1)
    var yesterday = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0")
    return iso === yesterday ? "yesterday" : iso.slice(5)
  }

  component Label: Text {
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  // A row with ‹ › at its ends: text, a muted aside and an optional bar (0..1).
  component Stepper: Item {
    id: step
    property string text: ""
    property string aside: ""
    property real bar: -1
    property bool canStep: true
    signal stepped(int dir)

    width: body.width
    height: Style.space(20)

    Repeater {
      model: step.canStep ? [-1, 1] : []

      Item {
        required property int modelData
        x: modelData < 0 ? 0 : step.width - width
        width: Style.space(18)
        height: step.height

        Icon {
          anchors.centerIn: parent
          d: parent.modelData < 0 ? Icons.back : Icons.forward
          size: Style.space(12)
          color: arrowMouse.containsMouse ? root.pal.strong : root.pal.muted
        }

        MouseArea {
          id: arrowMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: step.stepped(parent.modelData)
        }
      }
    }

    Row {
      id: tail
      anchors.right: parent.right
      anchors.rightMargin: step.canStep ? Style.space(22) : 0
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Label { anchors.verticalCenter: parent.verticalCenter; visible: step.aside !== ""; text: step.aside }

      Rectangle {
        visible: step.bar >= 0
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32)
        height: Style.space(4)
        radius: height / 2
        color: root.pal.alpha(root.pal.fg, 0.12)

        Rectangle {
          width: parent.width * Math.min(1, Math.max(0, step.bar))
          height: parent.height
          radius: parent.radius
          color: root.pal.crab
        }
      }
    }

    Label {
      x: step.canStep ? Style.space(22) : 0
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, tail.x - x - Style.space(6))
      color: root.pal.fg
      text: step.text
    }
  }

  Column {
    id: body
    width: parent.width
    spacing: Style.space(6)

    // Today against the quota, and the streak.
    Row {
      spacing: Style.space(6)

      Repeater {
        model: Math.max(root.perDay, root.doneToday)

        Rectangle {
          required property int index
          width: Style.space(8)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: index < root.doneToday ? root.pal.done : "transparent"
          border.width: 1
          border.color: index < root.doneToday ? root.pal.done : root.pal.muted
        }
      }

      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: root.doneToday + " of " + root.perDay + " today"
          + (root.streak ? " · " + root.streak + "-day streak" : "")
          + (root.redos ? " · " + root.redos + (root.redos === 1 ? " re-do" : " re-dos") + " due" : "")
      }
    }

    // The current challenge and its button.
    Item {
      width: parent.width
      height: Math.max(name.implicitHeight, buttons.implicitHeight)

      Text {
        id: name
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - buttons.width - Style.space(8))
        text: root.rep ? root.rep.name : root.langsOn.length ? "No challenge today." : "Anti-rot is off."
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Row {
        id: buttons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Pill {
          visible: root.inProgress
          pal: root.pal
          dense: true
          iconOnly: true
          icon: Icons.external
          tooltip: "Open"
          tooltipAbove: true
          onClicked: root.challenge("open")
        }
        Pill {
          visible: !root.rep
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: "secondary"
          icon: Icons.gear
          label: "Settings"
          onClicked: root.challenge("settings")
        }
        Pill {
          visible: !!root.rep && !root.rep.startedAt
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: "primary"
          icon: Icons.code
          label: "Start"
          busy: root.busy === "start"
          onClicked: root.challenge("start")
        }
        Pill {
          visible: root.inProgress
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: "primary"
          icon: Icons.check
          label: "Check"
          busy: root.busy === "check"
          onClicked: root.challenge("check")
        }
        Pill {
          visible: root.passed
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: root.doneToday < root.perDay ? "primary" : "secondary"
          label: root.doneToday < root.perDay ? "Next" : "Another one"
          busy: root.busy === "next"
          onClicked: root.challenge("next")
        }
      }
    }

    // Languages: level, progress to the next, usual solve time.
    Stepper {
      visible: root.langsOn.length > 0
      canStep: root.langsOn.length > 1
      text: root.langName(root.lang) + " · lv " + (root.langs[root.lang] ? root.langs[root.lang].level : "")
      aside: root.pace(root.lang)
      bar: root.langs[root.lang] ? (root.langs[root.lang].passes || 0) / root.passesToLevel : -1
      onStepped: function(dir) { root.langPick = (root.langAt + dir + root.langsOn.length) % root.langsOn.length }
    }

    // What's been done, newest first.
    Stepper {
      visible: root.recent.length > 0
      canStep: root.recent.length > 1
      text: root.recent.length ? root.recent[root.doneIdx].name + " · " + root.langName(root.recent[root.doneIdx].lang)
        + " · " + root.dayName(root.recent[root.doneIdx].date) + (root.recent[root.doneIdx].redo ? " · re-do" : "") : ""
      aside: (root.doneIdx + 1) + "/" + root.recent.length + (root.total > root.recent.length ? " of " + root.total : "")
      onStepped: function(dir) { root.doneAt = Math.min(root.recent.length - 1, Math.max(0, root.doneIdx - dir)) }
    }
  }
}
