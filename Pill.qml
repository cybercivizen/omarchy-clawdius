import QtQuick
import qs.Commons

// The island's button: fully rounded. "primary" is filled with ink (the main
// action), "secondary" a faint wash, "quiet" text only until hovered. With
// `busy` it breathes and spins in place of its icon, and ignores clicks.
Rectangle {
  id: root

  property QtObject pal
  property string label: ""
  // An Icon.qml path, drawn before the label (or alone with iconOnly).
  property string icon: ""
  property string kind: "secondary"
  property bool iconOnly: false
  property bool busy: false
  property bool compact: false
  // Smaller still, for dense rows (Settings, the corner card).
  property bool dense: false
  property string fontFamily: Style.font.family
  property string tooltip: ""
  property bool tooltipAbove: false   // at the foot of a card: over the pill

  signal clicked()

  readonly property bool primary: kind === "primary"
  readonly property bool hovered: mouse.containsMouse && !busy
  readonly property color ink: !pal ? "white"
    : primary ? pal.primaryInk
    : kind === "quiet" && !hovered ? pal.muted
    : pal.fg

  implicitHeight: Style.space(dense ? 24 : compact ? 30 : 36)
  implicitWidth: iconOnly ? implicitHeight : row.implicitWidth + Style.space(dense ? 18 : compact ? 24 : 32)
  radius: pal.pill(height)
  color: !pal ? "transparent"
    : primary ? (hovered ? pal.mix(pal.primary, pal.light ? "#ffffff" : "#000000", 0.12) : pal.primary)
    : kind === "quiet" ? (hovered ? pal.alpha(pal.fg, 0.06) : "transparent")
    : pal.alpha(pal.fg, hovered ? 0.16 : 0.10)
  scale: mouse.pressed ? 0.96 : 1

  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on scale { NumberAnimation { duration: 90 } }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(8)

    // A fixed slot for the icon or the spinner, so the width holds.
    Item {
      visible: root.icon !== "" || root.busy
      width: Style.space(14)
      height: width
      anchors.verticalCenter: parent.verticalCenter

      Icon {
        visible: !root.busy
        anchors.centerIn: parent
        d: root.icon
        size: Style.space(14)
        color: root.ink
      }

      Item {
        anchors.fill: parent
        visible: root.busy

        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: "transparent"
          border.width: 2
          border.color: root.pal ? root.pal.alpha(root.ink, 0.25) : "transparent"
        }

        Item {
          id: spinner
          anchors.fill: parent
          Spin { target: spinner; running: root.busy; period: 800 }

          Rectangle {
            width: Style.space(4)
            height: width
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.ink
          }
        }
      }
    }

    Text {
      visible: !root.iconOnly && root.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: root.label
      textFormat: Text.PlainText
      color: root.ink
      font.family: root.fontFamily
      font.pixelSize: root.compact ? Style.font.bodySmall : Style.font.body
      font.bold: true
    }
  }

  // Breathing while busy. Starts and ends at full strength.
  Throb { target: root; running: root.busy; low: 0.45 }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: !root.busy
    hoverEnabled: true
    cursorShape: root.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  // A plain hover label for icon-only pills.
  Rectangle {
    visible: root.tooltip !== "" && mouse.containsMouse
    x: (parent.width - width) / 2
    y: root.tooltipAbove ? -height - Style.space(6) : parent.height + Style.space(6)
    width: tipText.implicitWidth + Style.space(14)
    height: tipText.implicitHeight + Style.space(8)
    radius: pal.rad(Style.space(8))
    z: 20
    color: root.pal ? root.pal.raised : "black"
    border.width: 1
    border.color: root.pal ? root.pal.line : "transparent"

    Text {
      id: tipText
      anchors.centerIn: parent
      text: root.tooltip
      textFormat: Text.PlainText
      color: root.pal ? root.pal.fg : "white"
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
