import QtQuick
import Quickshell
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// The new chat view (the nav's chat icon, Super+Alt+C): what's typed lands in
// the key window's field (the card can't take keys) and is drawn here by
// MirrorInput. Chat or Code, whichever was used last; Enter starts that
// session with the message as its first prompt. `compact` is the view itself:
// no frame of its own. Without it, it's the chatbox typing opens over the
// other views of a summoned island.
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property var field: null
  property string mode: "chat"
  property string chatDir: ""
  property string codeDir: ""
  property int fontSize: Style.font.subtitle
  property bool compact: false
  property bool focused: true
  // The model new sessions start on: a `claude --model` alias, "" for Claude's
  // own default. The chip in the composer opens the choices under it.
  property string model: ""
  property bool modelsOpen: false
  readonly property var models: [
    { id: "", label: "Default" },
    { id: "fable", label: "Fable" },
    { id: "opus", label: "Opus" },
    { id: "sonnet", label: "Sonnet" },
    { id: "haiku", label: "Haiku" }
  ]
  readonly property string modelLabel: {
    for (var i = 0; i < models.length; i++) if (models[i].id === model) return models[i].label
    return model
  }
  // And its effort (`claude --effort`), "" for the default; the second row under the chip.
  property string effort: ""
  readonly property var efforts: [
    { id: "", label: "Default" },
    { id: "low", label: "Low" },
    { id: "medium", label: "Medium" },
    { id: "high", label: "High" },
    { id: "xhigh", label: "XHigh" },
    { id: "max", label: "Max" }
  ]
  readonly property string effortLabel: {
    for (var i = 0; i < efforts.length; i++) if (efforts[i].id === effort) return efforts[i].label
    return effort
  }
  readonly property string chipLabel: effort ? modelLabel + " · " + effortLabel : modelLabel
  // The folder Code starts in: "" for the Code folder. Its label opens the
  // choices: the Code folder, the one Claude worked in last, or any.
  property string dir: ""
  property string recentDir: ""
  property bool foldersOpen: false
  // Laid out like this, the field's caret lines up with the drawing.
  readonly property real inputWidth: shown.width

  signal picked(string mode)
  signal modelPicked(string model)
  signal effortPicked(string effort)
  signal dirPicked(string dir)
  signal browseRequested()
  signal send()
  // Clicked into the composer: the key window takes the keyboard back.
  signal focusRequested()

  readonly property string text: field ? field.text : ""
  readonly property string home: Quickshell.env("HOME") || ""

  readonly property real inset: compact ? Style.space(4) : Style.space(14)
  height: column.implicitHeight + inset * 2
  radius: Style.space(20)
  color: compact ? "transparent" : pal.card
  border.width: compact ? 0 : 1
  border.color: pal.alpha(pal.crab, 0.35)

  Column {
    id: column
    x: root.inset
    y: root.inset
    width: parent.width - root.inset * 2
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: toggle.height

      // Chat | Code, Tab switches.
      Rectangle {
        id: toggle
        width: toggleRow.implicitWidth + Style.space(4) * 2
        height: Style.space(32)
        radius: height / 2
        color: root.pal.alpha(root.pal.fg, 0.06)

        Row {
          id: toggleRow
          x: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Segment { which: "chat"; icon: Icons.chat; label: "Chat" }
          Segment { which: "code"; icon: Icons.code; label: "Code" }
        }
      }

      // In Code, the folder is a picker; click for the choices below.
      Item {
        anchors.left: toggle.right
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: dirRow.implicitWidth
        height: dirRow.implicitHeight

        Row {
          id: dirRow
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "code" ? Format.folder(root.dir || root.codeDir, root.home) + " · auto mode"
                                       : Format.folder(root.chatDir, root.home) + " · talk only"
            textFormat: Text.PlainText
            color: root.mode === "code" && (root.foldersOpen || dirMouse.containsMouse) ? root.pal.strong : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Icon {
            visible: root.mode === "code"
            anchors.verticalCenter: parent.verticalCenter
            d: "M6 9l6 6 6-6"
            size: Style.space(11)
            stroke: 2.4
            rotation: root.foldersOpen ? 180 : 0
            color: root.pal.muted
            Behavior on rotation { NumberAnimation { duration: 140 } }
          }
        }

        MouseArea {
          id: dirMouse
          enabled: root.mode === "code"
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.foldersOpen = !root.foldersOpen; root.modelsOpen = false; root.focusRequested() }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.compact && root.text === "" ? "Tab switch · Esc close" : "Tab switch · Esc clear"
        textFormat: Text.PlainText
        color: root.pal.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The composer, as LiveTerm draws its own.
    Rectangle {
      width: parent.width
      height: Math.max(Style.space(28), shown.implicitHeight) + Style.space(10) * 2
      radius: Math.min(height / 2, Style.space(22))
      color: root.pal.raised
      border.width: 1
      border.color: root.pal.alpha(root.pal.crab, 0.55)

      MirrorInput {
        id: shown
        x: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - modelChip.width - sendButton.width - Style.space(8) * 3
        pal: root.pal
        field: root.field
        focused: root.focused
        fontSize: root.fontSize
        fontFamily: root.fontFamily
        placeholder: root.mode === "code" ? "What should Claude build?" : "Ask Claude anything…"
        onFocusRequested: root.focusRequested()
      }

      // Model for the next session; click for the choices below.
      Rectangle {
        id: modelChip
        anchors.right: sendButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: chipRow.implicitWidth + Style.space(12) * 2
        height: Style.space(26)
        radius: height / 2
        color: root.modelsOpen ? root.pal.alpha(root.pal.fg, 0.14)
          : chipMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.10) : root.pal.alpha(root.pal.fg, 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }

        Row {
          id: chipRow
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.chipLabel
            textFormat: Text.PlainText
            color: root.model === "" && root.effort === "" ? root.pal.muted : root.pal.strong
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Icon {
            anchors.verticalCenter: parent.verticalCenter
            d: "M6 9l6 6 6-6"
            size: Style.space(12)
            stroke: 2.4
            rotation: root.modelsOpen ? 180 : 0
            color: root.pal.muted
            Behavior on rotation { NumberAnimation { duration: 140 } }
          }
        }

        MouseArea {
          id: chipMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.modelsOpen = !root.modelsOpen; root.foldersOpen = false; root.focusRequested() }
        }
      }

      Rectangle {
        id: sendButton
        readonly property bool ready: root.text.trim() !== ""
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32)
        height: width
        radius: width / 2
        color: ready ? root.pal.primary : root.pal.alpha(root.pal.fg, 0.08)

        Icon {
          anchors.centerIn: parent
          d: "M12 19V5M6 11l6-6 6 6"
          size: Style.space(16)
          stroke: 2.4
          color: sendButton.ready ? root.pal.primaryInk : root.pal.muted
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: sendButton.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (sendButton.ready) root.send()
        }
      }
    }

    // The choices, under the composer while the chip is open: model, then effort.
    Row {
      visible: root.modelsOpen
      spacing: Style.space(2)
      leftPadding: Style.space(4)

      Repeater {
        model: root.models
        Choice {
          label: modelData.label
          selected: root.model === modelData.id
          onPicked: { root.modelPicked(modelData.id); root.modelsOpen = false; root.focusRequested() }
        }
      }
    }

    Row {
      visible: root.modelsOpen
      spacing: Style.space(2)
      leftPadding: Style.space(4)

      Repeater {
        model: root.efforts
        Choice {
          label: modelData.label
          selected: root.effort === modelData.id
          onPicked: { root.effortPicked(modelData.id); root.modelsOpen = false; root.focusRequested() }
        }
      }
    }

    // Where Code starts, while its folder is open.
    Row {
      visible: root.foldersOpen && root.mode === "code"
      spacing: Style.space(2)
      leftPadding: Style.space(4)

      Choice {
        label: Format.folder(root.codeDir, root.home)
        selected: root.dir === ""
        onPicked: { root.dirPicked(""); root.foldersOpen = false; root.focusRequested() }
      }
      Choice {
        visible: root.recentDir !== "" && root.recentDir !== root.codeDir
        label: "Last: " + Format.folder(root.recentDir, root.home)
        selected: root.dir === root.recentDir
        onPicked: { root.dirPicked(root.recentDir); root.foldersOpen = false; root.focusRequested() }
      }
      Choice {
        visible: root.dir !== "" && root.dir !== root.recentDir
        label: Format.folder(root.dir, root.home)
        selected: true
        onPicked: { root.foldersOpen = false; root.focusRequested() }
      }
      Choice {
        label: "Open folder…"
        selected: false
        onPicked: { root.foldersOpen = false; root.browseRequested() }
      }
    }
  }

  component Choice: Rectangle {
    id: opt
    property string label: ""
    property bool selected: false
    signal picked()

    width: optText.implicitWidth + Style.space(12) * 2
    height: Style.space(26)
    radius: height / 2
    color: selected ? root.pal.alpha(root.pal.fg, 0.14) : optMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.06) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      id: optText
      anchors.centerIn: parent
      text: opt.label
      textFormat: Text.PlainText
      color: opt.selected ? root.pal.strong : root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: opt.selected
    }

    MouseArea {
      id: optMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: opt.picked()
    }
  }

  component Segment: Rectangle {
    id: seg
    property string which: ""
    property string icon: ""
    property string label: ""
    readonly property bool on: root.mode === which

    width: segRow.implicitWidth + Style.space(12) * 2
    height: Style.space(26)
    radius: height / 2
    color: on ? root.pal.alpha(root.pal.fg, 0.14) : segMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.06) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      id: segRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        d: seg.icon
        size: Style.space(13)
        color: seg.on ? root.pal.crab : root.pal.muted
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.label
        textFormat: Text.PlainText
        color: seg.on ? root.pal.strong : root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: seg.on
      }
    }

    MouseArea {
      id: segMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.picked(seg.which)
    }
  }
}
