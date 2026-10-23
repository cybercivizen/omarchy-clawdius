import QtQuick
import qs.Commons
import "Icons.js" as Icons

// The Anti-rot mode of Home's corner card: today's pips against the quota,
// the streak, each language's level and progress, the last few challenges
// done, and the one button that moves the current one on. It is how to ask
// for the next challenge while Claude is working and the left side is busy.
// The actions go to BarWidget as the challenge card's do.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // antirot.json, as antirot.py writes it.
  property var antirot: null
  // The antirot.py action running: "" | start | check | next | …
  property string busy: ""

  // start | open | check | next | settings
  signal challenge(string action)

  readonly property var rep: antirot ? antirot.today : null
  readonly property var info: antirot && antirot.info ? antirot.info : ({})
  readonly property var langs: antirot && antirot.langs ? antirot.langs : ({})
  readonly property var langsOn: Object.keys(langs).filter(function(l) { return langs[l].on }).sort()
  readonly property var recent: antirot && antirot.stats ? antirot.stats.recent : []
  readonly property var byLang: antirot && antirot.stats ? antirot.stats.byLang : ({})
  readonly property int redos: antirot && antirot.stats ? antirot.stats.redos : 0
  readonly property int total: antirot && antirot.stats ? antirot.stats.total : 0
  readonly property int perDay: antirot ? antirot.perDay || 1 : 1
  readonly property int doneToday: antirot ? antirot.doneToday || 0 : 0
  readonly property int streak: antirot ? antirot.streakNow || 0 : 0
  readonly property int passesToLevel: antirot ? antirot.passesToLevel || 2 : 2
  readonly property bool inProgress: !!rep && !!rep.startedAt && !rep.passedAt
  readonly property bool passed: !!rep && !!rep.passedAt

  implicitHeight: body.implicitHeight

  function langName(lang) { return info[lang] ? info[lang].name : lang }

  // " · ~14m (was 22m)": the usual solve time lately, and the five before.
  function pace(lang) {
    var m = byLang[lang]
    if (!m || !m.median) return ""
    return " · ~" + Math.max(1, Math.round(m.median / 60)) + "m" + (m.before ? " (was " + Math.max(1, Math.round(m.before / 60)) + "m)" : "")
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

  Column {
    id: body
    width: parent.width
    spacing: Style.space(10)

    // Today against the quota, and the streak.
    Row {
      spacing: Style.space(6)

      Repeater {
        model: Math.max(root.perDay, root.doneToday)

        Rectangle {
          required property int index
          width: Style.space(10)
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
          + (root.streak ? " · " + root.streak + (root.streak === 1 ? " day" : " days") + " in a row" : "")
          + (root.redos ? " · " + root.redos + (root.redos === 1 ? " re-do" : " re-dos") + " due" : "")
      }
    }

    // The current challenge and its button.
    Column {
      width: parent.width
      spacing: Style.space(6)

      Text {
        width: parent.width
        text: root.rep ? root.rep.name : root.langsOn.length ? "No challenge today." : "Anti-rot is off."
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Row {
        spacing: Style.space(6)

        Pill {
          visible: !root.rep
          pal: root.pal
          compact: true
          fontFamily: root.fontFamily
          kind: "secondary"
          icon: Icons.gear
          label: "Settings"
          onClicked: root.challenge("settings")
        }
        Pill {
          visible: !!root.rep && !root.rep.startedAt
          pal: root.pal
          compact: true
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
          compact: true
          fontFamily: root.fontFamily
          kind: "primary"
          icon: Icons.check
          label: "Check"
          busy: root.busy === "check"
          onClicked: root.challenge("check")
        }
        Pill {
          visible: root.inProgress
          pal: root.pal
          compact: true
          fontFamily: root.fontFamily
          icon: Icons.external
          label: "Open"
          onClicked: root.challenge("open")
        }
        Pill {
          visible: root.passed
          pal: root.pal
          compact: true
          fontFamily: root.fontFamily
          kind: root.doneToday < root.perDay ? "primary" : "secondary"
          label: root.doneToday < root.perDay ? "Next" : "Another one"
          busy: root.busy === "next"
          onClicked: root.challenge("next")
        }
      }
    }

    // Each language on: its level and how far to the next one.
    Repeater {
      model: root.langsOn

      Item {
        required property string modelData
        readonly property var prefs: root.langs[modelData]
        width: body.width
        height: Style.space(16)

        Label {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - bar.width - Style.space(10)
          text: root.langName(parent.modelData) + " · lv " + parent.prefs.level + root.pace(parent.modelData)
        }

        Rectangle {
          id: bar
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(48)
          height: Style.space(4)
          radius: height / 2
          color: root.pal.alpha(root.pal.fg, 0.12)

          Rectangle {
            width: parent.width * Math.min(1, (parent.parent.prefs.passes || 0) / root.passesToLevel)
            height: parent.height
            radius: parent.radius
            color: root.pal.crab
          }
        }
      }
    }

    // The last few done.
    Column {
      visible: root.recent.length > 0
      width: parent.width
      spacing: Style.space(2)

      Label { text: ("Done · " + root.total + " in all").toUpperCase(); font.letterSpacing: 0.8 }

      Repeater {
        model: root.recent

        Label {
          required property var modelData
          width: body.width
          color: root.pal.fg
          text: modelData.name + " · " + root.langName(modelData.lang) + " · " + root.dayName(modelData.date)
        }
      }
    }
  }
}
