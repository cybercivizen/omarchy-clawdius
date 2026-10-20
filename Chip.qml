import QtQuick
import qs.Commons

// The small tag after a session's name: `bg` for background sessions.
Rectangle {
  id: root

  property QtObject pal
  property string label: ""
  property string fontFamily: Style.font.family

  implicitWidth: chipText.implicitWidth + Style.space(12)
  implicitHeight: chipText.implicitHeight + Style.space(3)
  radius: Style.space(5)
  color: pal ? pal.alpha(pal.fg, 0.08) : "transparent"

  Text {
    id: chipText
    anchors.centerIn: parent
    text: root.label
    textFormat: Text.PlainText
    color: root.pal ? root.pal.muted : "gray"
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
