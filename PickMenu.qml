import QtQuick
import qs.Commons

// A chip's choices (model, effort, a folder, what to link): a small menu over
// whatever is under it, so nothing moves. Its owner places it: rising from
// the chip in the live view, dropping from it in the chat view. An option
// with `special` (Opus Plan) sits on a drifting Shimmer; one with a `tone`
// (effort's levels) gets its text in that color, a `hint` sits
// muted beside the label.
Rectangle {
  id: root

  property string title: ""
  // {id, label, special?, hint?, tone?}
  property var options: []
  property string current: ""
  property real minWidth: 0
  property color ink: Color.foreground
  property color quietInk: Qt.darker(ink, 1.45)
  property color hot: ink
  property color glow: hot
  property color fill: "transparent"

  signal picked(string id)

  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  readonly property real pad: Style.space(6)
  width: Math.max(menuColumn.implicitWidth, minWidth) + pad * 2
  height: menuColumn.implicitHeight + pad * 2
  radius: Style.space(12)
  color: fill
  border.width: 1
  border.color: tint(ink, 0.12)

  // A click on the padding stays in the menu.
  MouseArea { anchors.fill: parent }

  Column {
    id: menuColumn
    x: root.pad
    y: root.pad
    width: parent.width - root.pad * 2

    // A section label, as Home's and the + menu's: small caps, spaced out,
    // a hairline under it, so it doesn't read as one of the choices.
    Text {
      visible: root.title !== ""
      leftPadding: Style.space(10)
      topPadding: Style.space(5)
      bottomPadding: Style.space(6)
      text: root.title.toUpperCase()
      textFormat: Text.PlainText
      color: root.tint(root.quietInk, 0.75)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption - 1
      font.letterSpacing: 0.9
      font.bold: true
    }

    Rectangle {
      visible: root.title !== ""
      x: Style.space(6)
      width: parent.width - Style.space(12)
      height: 1
      color: root.tint(root.ink, 0.08)
    }

    Item { visible: root.title !== ""; width: 1; height: Style.space(4) }

    Repeater {
      model: root.options

      // Sized to its text, so the menu takes the widest; the hover and
      // the check span the menu's width.
      Item {
        id: option
        required property var modelData
        readonly property bool on: root.current === modelData.id
        readonly property bool special: !!modelData.special
        readonly property bool toned: modelData.tone !== undefined
        width: optionText.x + optionText.implicitWidth + (hintText.visible ? hintText.implicitWidth + Style.space(10) : 0)
               + Style.space(10) * 2 + Style.space(13)
        height: Style.space(28)

        Shimmer {
          visible: option.special
          width: menuColumn.width
          height: parent.height
          radius: Style.space(8)
          from: root.hot
          to: root.glow
          strength: optionMouse.containsMouse ? 0.32 : 0.2
          running: root.visible
        }

        Rectangle {
          visible: !option.special
          width: menuColumn.width
          height: parent.height
          radius: Style.space(8)
          color: optionMouse.containsMouse ? root.tint(root.ink, 0.08) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
        }

        Text {
          id: optionText
          x: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: option.modelData.label
          textFormat: Text.PlainText
          color: option.toned ? option.modelData.tone : option.on || option.special ? root.ink : root.quietInk
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          font.bold: option.on
        }

        Text {
          id: hintText
          visible: !!option.modelData.hint
          anchors.left: optionText.right
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: option.modelData.hint || ""
          textFormat: Text.PlainText
          color: root.quietInk
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Icon {
          visible: option.on
          x: menuColumn.width - Style.space(10) - size
          anchors.verticalCenter: parent.verticalCenter
          d: "M5 12l5 5 9-11"
          size: Style.space(13)
          stroke: 2.4
          color: root.hot
        }

        MouseArea {
          id: optionMouse
          width: menuColumn.width
          height: parent.height
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.picked(option.modelData.id)
        }
      }
    }
  }
}
