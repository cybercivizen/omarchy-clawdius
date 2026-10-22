import QtQuick
import qs.Commons

// A chip's choices (model, effort, a folder, what to link): a small menu over
// whatever is under it, so nothing moves. Its owner places it: rising from
// the chip in the live view, dropping from it in the chat view. An option
// with `special` (Opus Plan) sits on a drifting Shimmer, its `hint` beside it.
Rectangle {
  id: root

  property string title: ""
  // {id, label, special?, hint?}
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

    Text {
      visible: root.title !== ""
      leftPadding: Style.space(10)
      topPadding: Style.space(4)
      bottomPadding: Style.space(4)
      text: root.title
      textFormat: Text.PlainText
      color: root.quietInk
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: root.options

      // Sized to its text, so the menu takes the widest; the hover and
      // the check span the menu's width.
      Item {
        id: option
        required property var modelData
        readonly property bool on: root.current === modelData.id
        readonly property bool special: !!modelData.special
        width: optionText.implicitWidth + (hintText.visible ? hintText.implicitWidth + Style.space(10) : 0)
               + Style.space(10) * 3 + Style.space(13)
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
          color: option.on || option.special ? root.ink : root.quietInk
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
