import QtQuick
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// Today's challenge, in Home's idle moment: a small exercise to write by hand
// (antirot.py picks it from an Exercism track). Start copies it out and opens
// your editor; Check runs its tests; passes fill the day's quota (Settings)
// toward the streak, Next chains another, and Claude can review it (read only). With no language on, or
// one that still needs its toolchain, it says so and points at Settings.
// New chat stays at the end of the buttons.
Column {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // antirot.json, as antirot.py writes it.
  property var antirot: null
  property double now: Date.now()
  // The antirot.py action running: "" | start | check | easier | skip | next | set | setup
  property string busy: ""
  // The corner card is showing Stuck (explain / hints).
  property bool stuckOpen: false
  // Dense look: the text is a step smaller and the status line joins the buttons.
  readonly property bool dense: !!pal && pal.dense

  signal started()
  signal opened()
  signal checked()
  signal stuck()
  signal easier()
  signal skipped()
  signal nexted()
  signal reviewed()
  signal settingsOpened()
  signal newChat()

  readonly property var rep: antirot ? antirot.today : null
  readonly property var info: antirot && antirot.info ? antirot.info : ({})
  readonly property var langsOn: {
    var langs = antirot && antirot.langs ? antirot.langs : {}
    return Object.keys(langs).filter(function(l) { return langs[l].on })
  }
  // On, but its toolchain is missing: the first one, for the hint.
  readonly property string blocked: {
    for (var i = 0; i < langsOn.length; i++) {
      var x = info[langsOn[i]]
      if (x && x.missing && x.missing.length) return langsOn[i]
    }
    return ""
  }
  readonly property bool inProgress: !!rep && !!rep.startedAt && !rep.passedAt
  readonly property bool passed: !!rep && !!rep.passedAt
  readonly property var check: rep ? rep.check : null
  readonly property int perDay: antirot ? antirot.perDay || 1 : 1
  readonly property int doneToday: antirot ? antirot.doneToday || 0 : 0
  // Where the day's quota stands; a chained one past it is a bonus.
  readonly property string counter: passed ? doneToday + " OF " + perDay + " DONE"
    : doneToday >= perDay ? "BONUS" : (doneToday + 1) + " OF " + perDay + " TODAY"
  // Minutes the box allows, 0 for none; and how long this one has run.
  readonly property int timeBox: antirot ? antirot.timeBox || 0 : 0
  readonly property int minutesIn: rep && rep.startedAt ? Math.floor((now - rep.startedAt) / 60000) : 0
  readonly property bool over: inProgress && timeBox > 0 && minutesIn >= timeBox
  readonly property int streak: antirot ? antirot.streakNow || 0 : 0

  function langName(lang) { return info[lang] ? info[lang].name : lang }

  // How it's going: time in and tests passing, or done.
  readonly property string statusText: !rep ? ""
    : passed ? "Done" + (rep.secs ? " in " + Math.max(1, Math.round(rep.secs / 60)) + "m" : "")
      + (rep.checks > 1 ? " · " + rep.checks + " checks" : "")
      + " · " + streak + (streak === 1 ? " day" : " days") + " in a row"
    : inProgress ? Format.ago(now, rep.startedAt) + " in"
      + (timeBox ? (over ? " · " + (minutesIn - timeBox) + "m over" : " · " + (timeBox - minutesIn) + "m left") : "")
      + (check ? " · " + (check.total ? check.passed + "/" + check.total + " passing" : "doesn't run yet") : "")
    : "difficulty " + rep.difficulty + "/10" + (streak ? " · " + streak + " in a row" : "")
  readonly property color statusColor: passed ? pal.done : over ? pal.needsYou : pal.muted

  spacing: pal.sp(14)

  Column {
    width: parent.width
    spacing: Style.space(root.dense ? 3 : 5)

    Text {
      visible: !!root.rep
      width: parent.width
      text: root.rep ? ("ANTI-ROT · " + (root.rep.redo ? "RE-DO · " : "") + root.langName(root.rep.lang) + " · LEVEL " + root.rep.level + " · " + root.counter).toUpperCase() : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.8
    }

    Text {
      width: parent.width
      text: root.rep ? root.rep.name
        : root.busy === "set" || root.busy === "setup" ? "Setting up…"
        : root.blocked ? root.langName(root.blocked) + " needs " + root.info[root.blocked].missing.join(", ") + "."
        : root.langsOn.length ? "No challenge today."
        : "Anti-rot is off."
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.strong
      font.family: root.fontFamily
      font.pixelSize: root.dense ? Style.font.subtitle : Style.font.heading
      font.bold: true
    }

    Text {
      width: parent.width
      text: root.rep ? root.rep.blurb
        : root.busy === "set" || root.busy === "setup" ? "Getting the exercises. The first time takes a minute."
        : root.blocked ? "Install it, then open the island again: " + root.info[root.blocked].install
        : root.langsOn.length ? "Set up a language in Settings to get one."
        : "Small exercises, written by hand. Pick a language in Settings."
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: root.dense ? Style.font.bodySmall : Style.font.body
    }
  }

  // How it's going: time in and tests passing, or done.
  Row {
    visible: !!root.rep && !root.dense
    spacing: Style.space(8)

    Icon {
      visible: root.passed
      anchors.verticalCenter: parent.verticalCenter
      d: Icons.check
      size: Style.space(14)
      color: root.pal.done
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.statusText
      textFormat: Text.PlainText
      color: root.statusColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // The last check's output, while it isn't passing.
  Rectangle {
    visible: root.inProgress && !!root.check && root.check.tail !== ""
    width: parent.width
    height: tailText.implicitHeight + Style.space(16)
    radius: pal.rad(Style.space(10))
    color: root.pal.well

    Text {
      id: tailText
      x: Style.space(10)
      y: Style.space(8)
      width: parent.width - Style.space(20)
      text: root.check ? root.check.tail.split("\n").slice(root.dense ? -2 : -3).join("\n") : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: "monospace"
      font.pixelSize: Style.font.caption
    }
  }

  Flow {
    width: parent.width
    spacing: Style.space(8)

    Pill {
      compact: root.dense
      visible: !root.rep
      pal: root.pal
      fontFamily: root.fontFamily
      kind: "secondary"
      icon: Icons.gear
      label: "Settings"
      busy: root.busy === "set" || root.busy === "setup"
      onClicked: root.settingsOpened()
    }

    Pill {
      compact: root.dense
      visible: !!root.rep && !root.rep.startedAt
      pal: root.pal
      fontFamily: root.fontFamily
      kind: "primary"
      icon: Icons.code
      label: "Start"
      busy: root.busy === "start"
      onClicked: root.started()
    }
    Pill {
      compact: root.dense
      visible: !!root.rep && !root.rep.startedAt && root.rep.level > 1
      pal: root.pal
      fontFamily: root.fontFamily
      label: "Easier"
      busy: root.busy === "easier"
      onClicked: root.easier()
    }

    Pill {
      compact: root.dense
      visible: root.inProgress
      pal: root.pal
      fontFamily: root.fontFamily
      kind: "primary"
      icon: Icons.check
      label: "Check"
      busy: root.busy === "check"
      onClicked: root.checked()
    }
    Pill {
      compact: root.dense
      visible: root.inProgress
      pal: root.pal
      fontFamily: root.fontFamily
      icon: Icons.help
      label: root.stuckOpen ? "Hide help" : "Stuck?"
      tooltip: "Explain the task, or a hint"
      tooltipAbove: true
      onClicked: root.stuck()
    }
    Pill {
      compact: root.dense
      visible: root.inProgress
      pal: root.pal
      fontFamily: root.fontFamily
      icon: Icons.external
      label: "Open"
      onClicked: root.opened()
    }

    Pill {
      compact: root.dense
      visible: !!root.rep && !root.passed
      pal: root.pal
      fontFamily: root.fontFamily
      kind: "quiet"
      label: "Skip"
      busy: root.busy === "skip"
      onClicked: root.skipped()
    }

    // Chain another: the main action while the day's quota isn't met.
    Pill {
      compact: root.dense
      visible: root.passed
      pal: root.pal
      fontFamily: root.fontFamily
      kind: root.doneToday < root.perDay ? "primary" : "secondary"
      label: root.doneToday < root.perDay ? "Next" : "Another one"
      busy: root.busy === "next"
      onClicked: root.nexted()
    }

    Pill {
      compact: root.dense
      visible: root.passed
      pal: root.pal
      fontFamily: root.fontFamily
      icon: Icons.chat
      label: "Review"
      tooltip: "Review with Claude"
      tooltipAbove: true
      onClicked: root.reviewed()
    }

    // Into the chat view, as the idle moment always had: the main action
    // again once there's no rep left to do.
    Pill {
      compact: root.dense
      pal: root.pal
      fontFamily: root.fontFamily
      kind: !root.rep ? "primary" : "quiet"
      icon: Icons.chat
      label: "New chat"
      iconOnly: !!root.rep
      tooltip: "New chat"
      tooltipAbove: true
      onClicked: root.newChat()
    }

    // Dense: the status line, after the buttons.
    Text {
      visible: root.dense && !!root.rep
      height: Style.space(26)
      leftPadding: Style.space(4)
      verticalAlignment: Text.AlignVCenter
      text: root.statusText
      textFormat: Text.PlainText
      color: root.statusColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
