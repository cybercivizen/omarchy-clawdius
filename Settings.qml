import QtQuick
import qs.Commons
import "Icons.js" as Icons
import "Timers.js" as Timers

// The gear's view: settings that live in the island rather than shell.json.
// One section per feature, stacked and foldable; a new setting is a new
// section here.
//
//   Island      where sessions open: in the island, or in a terminal window.
//   Move        how often the sit-up and the stand-up-and-walk nudges ring
//               (the switches are on Home's Move card).
//   Anti-rot    how many challenges a day, which languages are in the rotation,
//               and each one's level (antirot.py keeps them in antirot.json),
//               languages to add, and the editor challenges open in.
Column {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // antirot.json, as antirot.py writes it.
  property var antirot: null
  // The antirot.py action running ("set", "level", "setup"…) and its language.
  property string busy: ""
  property string busyLang: ""
  // {on, everyMin, …} of the two nudges, as BarWidget keeps them.
  property var posture: ({ everyMin: 30 })
  property var walk: ({ everyMin: 60 })
  // Sessions open in a terminal window, never in the island.
  property bool terminalOutside: false

  signal terminalOutsideSet(bool on)
  signal lookSet(string look)
  signal nudgeSet(string key, int everyMin)
  signal langToggled(string lang, bool on)
  signal levelSet(string lang, int level)
  signal setupAsked(string lang)
  signal editorSet(string editor)
  signal oftenSet(int perDay)
  signal timeBoxSet(int minutes)
  signal langAdded(string track)
  signal langRemoved(string lang)

  // [label, command]; "" is Omarchy's default editor.
  readonly property var editors: [["Default", ""], ["Neovim", "nvim"], ["Helix", "hx"], ["Nano", "nano"], ["VS Code", "code"], ["Zed", "zeditor"]]
  readonly property string editor: antirot && antirot.editor ? antirot.editor : ""

  readonly property var info: antirot && antirot.info ? antirot.info : ({})
  readonly property var langs: antirot && antirot.langs ? antirot.langs : ({})
  readonly property var presets: antirot && antirot.presets ? antirot.presets : ({})
  readonly property int perDay: antirot ? antirot.perDay || 1 : 1
  readonly property int timeBox: antirot ? antirot.timeBox || 0 : 0
  readonly property int streak: antirot ? antirot.streakNow || 0 : 0

  spacing: Style.space(12)

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0.8
  }

  // A section: a header that folds its body.
  component Section: Column {
    id: section
    property string title: ""
    property bool open: true
    default property alias content: body.data
    width: parent.width
    spacing: Style.space(6)

    MouseArea {
      width: parent.width
      height: Style.space(24)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: section.open = !section.open

      Caption {
        anchors.verticalCenter: parent.verticalCenter
        text: section.title
      }

      Icon {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        d: Icons.chevron
        size: Style.space(14)
        color: parent.containsMouse ? root.pal.fg : root.pal.muted
        rotation: section.open ? 0 : -90
      }
    }

    Column {
      id: body
      visible: section.open
      width: parent.width
      spacing: Style.space(6)
    }
  }

  // An on / off switch.
  component Toggle: Rectangle {
    id: toggle
    property bool on: false
    property bool busy: false
    signal toggled(bool on)
    width: Style.space(36)
    height: Style.space(20)
    radius: root.pal.pill(height)
    color: on ? root.pal.primary : root.pal.alpha(root.pal.fg, toggleMouse.containsMouse ? 0.18 : 0.12)
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      x: toggle.on ? parent.width - width - Style.space(3) : Style.space(3)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.height - Style.space(6)
      height: width
      radius: width / 2
      color: toggle.on ? root.pal.primaryInk : root.pal.fg
      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      id: toggleMouse
      anchors.fill: parent
      enabled: !toggle.busy
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: toggle.toggled(!toggle.on)
    }
  }

  // A setting: its name, then its choices on the same line.
  component Setting: Flow {
    property string name: ""
    width: parent.width
    spacing: Style.space(6)

    Text {
      height: Style.space(24)
      width: Style.space(70)
      verticalAlignment: Text.AlignVCenter
      text: parent.name
      textFormat: Text.PlainText
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // ---- Island
  Section {
    title: "ISLAND"

    Text {
      width: parent.width
      text: "Sessions still show here, with approvals and usage. On, opening one (or starting one) puts it in a terminal window instead of the island."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Item {
      width: parent.width
      height: Style.space(24)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Terminals outside the island"
        textFormat: Text.PlainText
        color: root.pal.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Toggle {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        on: root.terminalOutside
        onToggled: function(on) { root.terminalOutsideSet(on) }
      }
    }

    Setting {
      name: "Theme"

      Repeater {
        model: [["Soft", "soft"], ["Compact", "dev"]]

        Pill {
          required property var modelData
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: root.pal.look === modelData[1] ? "primary" : "secondary"
          label: modelData[0]
          onClicked: root.lookSet(modelData[1])
        }
      }
    }

    Text {
      width: parent.width
      text: "Compact: small corners, hairline borders and tighter rows, to sit with the rest of the bar."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ---- Move
  Section {
    title: "MOVE"

    Text {
      width: parent.width
      text: "The crab's nudges on Home's Move card: sit up straight, and stand up and walk. Time away from the keyboard counts as a break."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    // A nudge's wait: the chips, or Custom with − / + (5 to 180 minutes).
    component Wait: Column {
      id: wait
      property string key: ""
      property string name: ""
      property var choices: []
      property var info: ({})
      property bool custom: false
      readonly property bool customShown: custom || choices.indexOf(info.everyMin) < 0
      width: parent.width
      spacing: Style.space(6)

      Setting {
        name: wait.name

        Repeater {
          model: wait.choices

          Pill {
            required property int modelData
            pal: root.pal
            dense: true
            fontFamily: root.fontFamily
            kind: !wait.customShown && wait.info.everyMin === modelData ? "primary" : "secondary"
            label: modelData + " min"
            onClicked: { wait.custom = false; root.nudgeSet(wait.key, modelData) }
          }
        }

        Pill {
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: wait.customShown ? "primary" : "secondary"
          label: "Custom"
          onClicked: wait.custom = true
        }
      }

      Item {
        visible: wait.customShown
        width: parent.width
        height: Style.space(24)

        Pill {
          pal: root.pal
          dense: true
          iconOnly: true
          icon: Icons.minus
          onClicked: root.nudgeSet(wait.key, Math.max(5, Timers.step(wait.info.everyMin, -1)))
        }

        Text {
          anchors.centerIn: parent
          text: "every " + Timers.span(wait.info.everyMin)
          textFormat: Text.PlainText
          color: root.pal.strong
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Pill {
          anchors.right: parent.right
          pal: root.pal
          dense: true
          iconOnly: true
          icon: Icons.plus
          onClicked: root.nudgeSet(wait.key, Math.min(180, Timers.step(wait.info.everyMin, 1)))
        }
      }
    }

    Wait { key: "posture"; name: "Sit up"; choices: Timers.intervals; info: root.posture }
    Wait { key: "walk"; name: "Walk"; choices: Timers.walkIntervals; info: root.walk }
  }

  // ---- Anti-rot
  Section {
    title: "ANTI-ROT"
    open: false

    Text {
      width: parent.width
      text: "Exercism exercises, written by hand. Languages take turns; two passes level one up. Over the time box, or four tries: it comes back as a re-do a week later."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Setting {
      name: "A day"

      Repeater {
        model: [1, 2, 3]

        Pill {
          required property int modelData
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: root.perDay === modelData ? "primary" : "secondary"
          label: String(modelData)
          onClicked: root.oftenSet(modelData)
        }
      }
    }

    Setting {
      name: "Time box"

      Repeater {
        model: [0, 15, 25, 45]

        Pill {
          required property int modelData
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: root.timeBox === modelData ? "primary" : "secondary"
          label: modelData ? modelData + " min" : "Off"
          onClicked: root.timeBoxSet(modelData)
        }
      }
    }

    Setting {
      name: "Editor"

      Repeater {
        model: root.editors

        Pill {
          required property var modelData
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          kind: root.editor === modelData[1] ? "primary" : "secondary"
          label: modelData[0]
          onClicked: root.editorSet(modelData[1])
        }
      }
    }

    Setting {
      visible: presetList.count > 0
      name: "Add track"

      Repeater {
        id: presetList
        model: Object.keys(root.presets).sort()

        Pill {
          required property string modelData
          pal: root.pal
          dense: true
          fontFamily: root.fontFamily
          icon: Icons.plus
          label: root.presets[modelData]
          busy: root.busy === "add" && root.busyLang === modelData
          onClicked: root.langAdded(modelData)
        }
      }
    }

    Repeater {
      model: Object.keys(root.info).sort()

      Rectangle {
        id: langRow
        required property string modelData
        readonly property var about: root.info[modelData] || ({})
        readonly property var prefs: root.langs[modelData] || ({ on: false, level: 2 })
        readonly property bool missing: !!about.missing && about.missing.length > 0
        readonly property bool working: root.busyLang === modelData && root.busy !== ""
        width: parent.width
        height: Style.space(40) + (installText.visible ? installText.implicitHeight + Style.space(4) : 0)
        radius: pal.rad(Style.space(12))
        color: root.pal.raised

        Row {
          x: Style.space(12)
          height: Style.space(40)
          width: parent.width - controls.width - Style.space(30)
          spacing: Style.space(8)

          Text {
            id: langName
            anchors.verticalCenter: parent.verticalCenter
            text: langRow.about.name || langRow.modelData
            textFormat: Text.PlainText
            color: root.pal.strong
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - langName.width - parent.spacing)
            text: langRow.working ? "setting up…"
              : langRow.missing ? "needs " + langRow.about.missing.join(", ")
              : langRow.about.ready ? (langRow.prefs.on ? "in the rotation" : "ready")
              : "not set up"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: langRow.missing ? root.pal.needsYouText : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          id: installText
          visible: langRow.missing
          x: Style.space(12)
          y: Style.space(34)
          width: parent.width - Style.space(24)
          text: langRow.about.install || ""
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.pal.muted
          font.family: "monospace"
          font.pixelSize: Style.font.caption
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          height: Style.space(40)
          spacing: Style.space(8)

          Pill {
            visible: !!langRow.about.custom
            anchors.verticalCenter: parent.verticalCenter
            pal: root.pal
            dense: true
            iconOnly: true
            icon: Icons.close
            tooltip: "Remove"
            onClicked: root.langRemoved(langRow.modelData)
          }

          Pill {
            visible: !langRow.missing && !langRow.about.setUp && langRow.prefs.on
            anchors.verticalCenter: parent.verticalCenter
            pal: root.pal
            dense: true
            fontFamily: root.fontFamily
            label: "Set up"
            busy: langRow.working
            onClicked: root.setupAsked(langRow.modelData)
          }

          // The level: − N +
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Pill {
              pal: root.pal
              dense: true
              iconOnly: true
              icon: Icons.minus
              tooltip: "Easier"
              onClicked: if (langRow.prefs.level > 1) root.levelSet(langRow.modelData, langRow.prefs.level - 1)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(40)
              horizontalAlignment: Text.AlignHCenter
              text: "lv " + langRow.prefs.level
              textFormat: Text.PlainText
              color: root.pal.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Pill {
              pal: root.pal
              dense: true
              iconOnly: true
              icon: Icons.plus
              tooltip: "Harder"
              onClicked: if (langRow.prefs.level < 10) root.levelSet(langRow.modelData, langRow.prefs.level + 1)
            }
          }

          Toggle {
            anchors.verticalCenter: parent.verticalCenter
            on: !!langRow.prefs.on
            busy: langRow.working
            onToggled: function(on) { root.langToggled(langRow.modelData, on) }
          }
        }
      }
    }

    Text {
      width: parent.width
      text: "Other tracks: antirot.py add TRACK NAME TOOLS \"TEST COMMAND\" · saved in "
        + (root.antirot && root.antirot.reps ? root.antirot.reps.replace(/^\/home\/[^\/]+/, "~") : "~/Work/antirot")
        + (root.streak ? " · " + root.streak + "-day streak" : "")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
