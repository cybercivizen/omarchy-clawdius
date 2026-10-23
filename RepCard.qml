import QtQuick
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// Today's rep, in Home's idle moment: one small exercise to write by hand
// (gym.py picks it from an Exercism track). Start copies it out and opens
// your editor; Check runs its tests; a pass counts the day toward the
// streak, and Claude can review it (read only). With no language on, or
// one that still needs its toolchain, it says so and points at Settings.
// New chat stays at the end of the buttons.
Column {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // gym.json, as gym.py writes it.
  property var gym: null
  property double now: Date.now()
  // The gym.py action running: "" | start | check | easier | skip | set | setup
  property string busy: ""

  signal started()
  signal opened()
  signal checked()
  signal easier()
  signal skipped()
  signal reviewed()
  signal settingsOpened()
  signal newChat()

  readonly property var rep: gym ? gym.today : null
  readonly property var info: gym && gym.info ? gym.info : ({})
  readonly property var langsOn: {
    var langs = gym && gym.langs ? gym.langs : {}
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
  readonly property int streak: gym ? gym.streakNow || 0 : 0

  function langName(lang) { return info[lang] ? info[lang].name : lang }

  spacing: Style.space(14)

  Column {
    width: parent.width
    spacing: Style.space(5)

    Text {
      visible: !!root.rep
      width: parent.width
      text: root.rep ? ("TODAY'S REP · " + root.langName(root.rep.lang) + " · LEVEL " + root.rep.level).toUpperCase() : ""
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
        : root.langsOn.length ? "No rep today."
        : "Daily reps are off."
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.strong
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Text {
      width: parent.width
      text: root.rep ? root.rep.blurb
        : root.busy === "set" || root.busy === "setup" ? "Getting the exercises. The first time takes a minute."
        : root.blocked ? "Install it, then open the island again: " + root.info[root.blocked].install
        : root.langsOn.length ? "Set up a language in Settings to get one."
        : "One small exercise a day, written by hand. Pick a language in Settings."
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  // How it's going: time in and tests passing, or done.
  Row {
    visible: !!root.rep
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
      text: root.passed ? "Done · " + root.streak + (root.streak === 1 ? " day" : " days") + " in a row"
        : root.inProgress ? Format.ago(root.now, root.rep.startedAt) + " in"
          + (root.check ? " · " + (root.check.total ? root.check.passed + "/" + root.check.total + " passing" : "doesn't run yet") : "")
        : "difficulty " + (root.rep ? root.rep.difficulty : 0) + "/10" + (root.streak ? " · " + root.streak + " in a row" : "")
      textFormat: Text.PlainText
      color: root.passed ? root.pal.done : root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // The last check's output, while it isn't passing.
  Rectangle {
    visible: root.inProgress && !!root.check && root.check.tail !== ""
    width: parent.width
    height: tailText.implicitHeight + Style.space(16)
    radius: Style.space(10)
    color: root.pal.well

    Text {
      id: tailText
      x: Style.space(10)
      y: Style.space(8)
      width: parent.width - Style.space(20)
      text: root.check ? root.check.tail.split("\n").slice(-3).join("\n") : ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: "monospace"
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    spacing: Style.space(8)

    Pill {
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
      visible: !!root.rep && !root.rep.startedAt && root.rep.level > 1
      pal: root.pal
      fontFamily: root.fontFamily
      label: "Easier"
      busy: root.busy === "easier"
      onClicked: root.easier()
    }

    Pill {
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
      visible: root.inProgress
      pal: root.pal
      fontFamily: root.fontFamily
      icon: Icons.external
      label: "Open"
      onClicked: root.opened()
    }

    Pill {
      visible: !!root.rep && !root.passed
      pal: root.pal
      fontFamily: root.fontFamily
      kind: "quiet"
      label: "Skip"
      busy: root.busy === "skip"
      onClicked: root.skipped()
    }

    Pill {
      visible: root.passed
      pal: root.pal
      fontFamily: root.fontFamily
      icon: Icons.chat
      label: "Review with Claude"
      onClicked: root.reviewed()
    }

    // Into the chat view, as the idle moment always had: the main action
    // again once there's no rep left to do.
    Pill {
      pal: root.pal
      fontFamily: root.fontFamily
      kind: !root.rep || root.passed ? "primary" : "quiet"
      icon: Icons.chat
      label: "New chat"
      onClicked: root.newChat()
    }
  }
}
