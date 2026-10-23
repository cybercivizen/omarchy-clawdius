import QtQuick
import qs.Commons
import "Icons.js" as Icons

// The gear's view: settings that live in the island rather than shell.json.
// One section per feature, stacked; a new setting is a new section here.
//
//   Daily reps  which languages are in the rotation, and each one's level
//               (gym.py keeps both in gym.json), languages to add, and the
//               editor reps open in.
Column {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // gym.json, as gym.py writes it.
  property var gym: null
  // The gym.py action running ("set", "level", "setup"…) and its language.
  property string busy: ""
  property string busyLang: ""

  signal langToggled(string lang, bool on)
  signal levelSet(string lang, int level)
  signal setupAsked(string lang)
  signal editorSet(string editor)
  signal langAdded(string track)
  signal langRemoved(string lang)

  // [label, command]; "" is Omarchy's default editor.
  readonly property var editors: [["Default", ""], ["Neovim", "nvim"], ["Helix", "hx"], ["Nano", "nano"], ["VS Code", "code"], ["Zed", "zeditor"]]
  readonly property string editor: gym && gym.editor ? gym.editor : ""

  readonly property var info: gym && gym.info ? gym.info : ({})
  readonly property var langs: gym && gym.langs ? gym.langs : ({})
  readonly property var presets: gym && gym.presets ? gym.presets : ({})
  readonly property int streak: gym ? gym.streakNow || 0 : 0

  spacing: Style.space(16)

  component Caption: Text {
    textFormat: Text.PlainText
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 0.8
  }

  // ---- Daily reps
  Column {
    width: parent.width
    spacing: Style.space(10)

    Caption { text: "DAILY REPS" }

    Text {
      width: parent.width
      text: "One small exercise a day from Exercism, written by hand. The languages on here take turns; a level goes up after two passes."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
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
        height: Style.space(60) + (installText.visible ? installText.implicitHeight + Style.space(6) : 0)
        radius: Style.space(16)
        color: root.pal.raised

        Column {
          x: Style.space(16)
          y: Style.space(12)
          width: parent.width - controls.width - Style.space(44)
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: langRow.about.name || langRow.modelData
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.pal.strong
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            width: parent.width
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

          Text {
            id: installText
            visible: langRow.missing
            width: parent.width
            topPadding: Style.space(4)
            text: langRow.about.install || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.pal.muted
            font.family: "monospace"
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          y: Style.space(15)
          spacing: Style.space(10)

          Pill {
            visible: !!langRow.about.custom
            anchors.verticalCenter: parent.verticalCenter
            pal: root.pal
            compact: true
            iconOnly: true
            icon: Icons.close
            tooltip: "Remove"
            onClicked: root.langRemoved(langRow.modelData)
          }

          Pill {
            visible: !langRow.missing && !langRow.about.setUp && langRow.prefs.on
            anchors.verticalCenter: parent.verticalCenter
            pal: root.pal
            compact: true
            fontFamily: root.fontFamily
            label: "Set up"
            busy: langRow.working
            onClicked: root.setupAsked(langRow.modelData)
          }

          // The level: − N +
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Pill {
              pal: root.pal
              compact: true
              iconOnly: true
              icon: Icons.minus
              tooltip: "Easier"
              onClicked: if (langRow.prefs.level > 1) root.levelSet(langRow.modelData, langRow.prefs.level - 1)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(62)
              horizontalAlignment: Text.AlignHCenter
              text: "level " + langRow.prefs.level
              textFormat: Text.PlainText
              color: root.pal.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Pill {
              pal: root.pal
              compact: true
              iconOnly: true
              icon: Icons.plus
              tooltip: "Harder"
              onClicked: if (langRow.prefs.level < 10) root.levelSet(langRow.modelData, langRow.prefs.level + 1)
            }
          }

          // On / off.
          Rectangle {
            id: toggle
            readonly property bool on: !!langRow.prefs.on
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(40)
            height: Style.space(22)
            radius: height / 2
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
              enabled: !langRow.working
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.langToggled(langRow.modelData, !toggle.on)
            }
          }
        }
      }
    }

    Flow {
      visible: presetList.count > 0
      width: parent.width
      spacing: Style.space(6)

      Text {
        height: Style.space(30)
        verticalAlignment: Text.AlignVCenter
        text: "Add"
        textFormat: Text.PlainText
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Repeater {
        id: presetList
        model: Object.keys(root.presets).sort()

        Pill {
          required property string modelData
          pal: root.pal
          compact: true
          fontFamily: root.fontFamily
          icon: Icons.plus
          label: root.presets[modelData]
          busy: root.busy === "add" && root.busyLang === modelData
          onClicked: root.langAdded(modelData)
        }
      }
    }

    Text {
      width: parent.width
      text: "Any other Exercism track: gym.py add TRACK NAME TOOLS \"TEST COMMAND\""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Caption { text: "EDITOR" }

    Flow {
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: root.editors

        Pill {
          required property var modelData
          pal: root.pal
          compact: true
          fontFamily: root.fontFamily
          kind: root.editor === modelData[1] ? "primary" : "secondary"
          label: modelData[0]
          onClicked: root.editorSet(modelData[1])
        }
      }
    }

    Text {
      width: parent.width
      text: "Reps are saved in " + (root.gym && root.gym.reps ? root.gym.reps.replace(/^\/home\/[^\/]+/, "~") : "~/Work/gym")
        + (root.streak ? " · " + root.streak + (root.streak === 1 ? " day" : " days") + " in a row" : "")
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
