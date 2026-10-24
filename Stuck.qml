import QtQuick
import qs.Commons

// The Stuck mode of Home's corner card, for a rep in progress: Explain (the
// task in plain words, with worked examples, for when the instructions make
// no sense) and Hint (nudges, each a step further). Both are asked of Claude
// by antirot.py and kept in antirot.json, so asking again is a button, and
// what's there is just shown. The corner card scrolls it when it's long.
Column {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // today's rep, as antirot.py writes it.
  property var rep: null
  // The antirot.py action running: "explain" | "hint" | other.
  property string busy: ""
  // explain | hint
  property string tab: "explain"

  signal explainAsked(bool again)
  signal hintAsked()

  readonly property string explainText: rep && rep.explain ? rep.explain : ""
  readonly property var hints: rep && rep.hints ? rep.hints : []
  readonly property int hintTotal: rep && rep.hintCount ? rep.hintCount : 0
  // What just arrived is what to look at.
  onExplainTextChanged: if (explainText) tab = "explain"
  onHintTotalChanged: if (hintTotal) tab = "hint"
  Component.onCompleted: if (!explainText && hintTotal) tab = "hint"

  spacing: Style.space(10)

  Row {
    spacing: Style.space(2)

    Repeater {
      model: [{ id: "explain", name: "Explain" }, { id: "hint", name: "Hint" }]

      Rectangle {
        required property var modelData
        readonly property bool current: root.tab === modelData.id
        width: tabLabel.implicitWidth + Style.space(18)
        height: Style.space(22)
        radius: pal.pill(height)
        color: current ? root.pal.alpha(root.pal.fg, 0.14) : root.pal.alpha(root.pal.fg, tabMouse.containsMouse ? 0.06 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
          id: tabLabel
          anchors.centerIn: parent
          text: parent.modelData.name
          textFormat: Text.PlainText
          color: parent.current ? root.pal.strong : root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: tabMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.tab = parent.modelData.id
        }
      }
    }
  }

  // ---- Explain
  Column {
    visible: root.tab === "explain"
    width: parent.width
    spacing: Style.space(10)

    Text {
      width: parent.width
      text: root.explainText || "The task in plain words, with worked examples."
      textFormat: root.explainText ? Text.MarkdownText : Text.PlainText
      wrapMode: Text.Wrap
      color: root.explainText ? root.pal.strong : root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Pill {
      pal: root.pal
      fontFamily: root.fontFamily
      dense: true
      kind: root.explainText ? "quiet" : "primary"
      label: root.explainText ? "Simpler" : "Explain it"
      tooltip: root.explainText ? "Explain it again, plainer" : ""
      busy: root.busy === "explain"
      onClicked: root.explainAsked(!!root.explainText)
    }
  }

  // ---- Hint
  Column {
    visible: root.tab === "hint"
    width: parent.width
    spacing: Style.space(10)

    Text {
      visible: root.hints.length === 0
      width: parent.width
      text: "A nudge, never the code. Each one goes a step further."
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Repeater {
      model: root.hints

      Text {
        required property int index
        required property string modelData
        width: root.width
        text: (root.hintTotal - root.hints.length + index + 1) + ". " + modelData
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: index === root.hints.length - 1 ? root.pal.strong : root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Pill {
      pal: root.pal
      fontFamily: root.fontFamily
      dense: true
      kind: root.hints.length ? "quiet" : "primary"
      label: root.hints.length ? "Another hint" : "Get a hint"
      busy: root.busy === "hint"
      onClicked: root.hintAsked()
    }
  }
}
