import QtQuick
import Quickshell
import qs.Commons
import "Format.js" as Format

// Claude Code's workspace trust question, asked in the card: a background
// session won't start in a folder whose trust isn't saved, and Claude only
// asks in a terminal. "Trust" saves it (live.py trust) and the session
// starts in the card; "Terminal" opens it in one, where Claude asks itself.
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property string dir: ""
  property bool saving: false

  signal answered(string choice)

  readonly property string home: Quickshell.env("HOME") || ""

  height: column.implicitHeight + Style.space(18) * 2
  radius: pal.rad(Style.space(20))
  color: pal.card
  border.width: 1
  border.color: pal.alpha(pal.needsYou, 0.45)

  onDirChanged: if (dir) popIn.restart()
  NumberAnimation {
    id: popIn
    target: root
    property: "scale"
    from: 0.97
    to: 1
    duration: 260
    easing.type: Easing.OutBack
  }

  Column {
    id: column
    x: Style.space(18)
    y: Style.space(18)
    width: parent.width - Style.space(18) * 2
    spacing: Style.space(12)

    Row {
      width: parent.width
      spacing: Style.space(8)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8)
        height: width
        radius: width / 2
        color: root.pal.needsYou
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "Do you trust the files in this folder?"
        textFormat: Text.PlainText
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }

    Rectangle {
      width: Math.min(parent.width, dirText.implicitWidth + Style.space(14) * 2)
      height: dirText.implicitHeight + Style.space(10) * 2
      radius: pal.rad(Style.space(12))
      color: root.pal.well
      border.width: 1
      border.color: root.pal.alpha(root.pal.fg, 0.10)

      Text {
        id: dirText
        x: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.width - Style.space(18) * 2 - Style.space(14) * 2)
        text: Format.folder(root.dir, root.home)
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }
    }

    Text {
      width: parent.width
      text: "Claude Code may read, write, or execute files contained in this folder and everything in it. "
        + "This can pose security risks, so only use files from trusted sources."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: parent.width
      height: buttons.implicitHeight

      Row {
        id: buttons
        spacing: Style.space(8)
        Pill { pal: root.pal; fontFamily: root.fontFamily; label: "No"; onClicked: root.answered("no") }
        Pill {
          pal: root.pal
          fontFamily: root.fontFamily
          label: "Yes, I trust this folder"
          kind: "primary"
          busy: root.saving
          onClicked: root.answered("yes")
        }
      }

      Pill {
        anchors.right: parent.right
        pal: root.pal
        fontFamily: root.fontFamily
        label: "Terminal"
        kind: "quiet"
        onClicked: root.answered("terminal")
      }
    }
  }
}
