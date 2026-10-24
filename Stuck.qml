import QtQuick
import qs.Commons
import "Icons.js" as Icons

// The Stuck mode of Home's corner card, for a rep in progress: Explain (the
// task in plain words, with worked examples, for when the instructions make
// no sense) and Hint (nudges, each a step further, paged one at a time). Both
// are asked of Claude by antirot.py and kept in antirot.json, so asking again
// is a button, and what's there is just shown. It fills the height it's given
// (the Anti-rot card's) and scrolls what doesn't fit, with a bar.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  // today's rep, as antirot.py writes it.
  property var rep: null
  // The antirot.py action running: "explain" | "hint" | other.
  property string busy: ""
  // explain | hint
  property string tab: "explain"
  // Which of the kept hints is shown.
  property int page: 0

  signal explainAsked(bool again)
  signal hintAsked()

  readonly property string explainText: rep && rep.explain ? rep.explain : ""
  readonly property var hints: rep && rep.hints ? rep.hints : []
  readonly property int hintTotal: rep && rep.hintCount ? rep.hintCount : 0
  readonly property real gap: Style.space(10)
  // What just arrived is what to look at.
  onExplainTextChanged: if (explainText) tab = "explain"
  onHintTotalChanged: if (hintTotal) { tab = "hint"; page = Math.max(0, hints.length - 1) }
  onTabChanged: flick.contentY = 0
  onPageChanged: flick.contentY = 0
  Component.onCompleted: {
    page = Math.max(0, hints.length - 1)
    if (!explainText && hintTotal) tab = "hint"
  }

  Row {
    id: tabs
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

  // ---- The text: the explanation, or the hint on this page.
  Flickable {
    id: flick
    y: tabs.height + root.gap
    width: parent.width
    height: Math.max(0, actions.y - root.gap - y)
    contentHeight: body.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Text {
      id: body
      width: flick.width - Style.space(12)
      text: root.tab === "explain"
        ? (root.explainText || "The task in plain words, with worked examples.")
        : (root.hints.length ? root.hints[Math.min(root.page, root.hints.length - 1)] : "A nudge, never the code. Each one goes a step further.")
      textFormat: root.tab === "explain" && root.explainText ? Text.MarkdownText : Text.PlainText
      wrapMode: Text.Wrap
      color: (root.tab === "explain" ? root.explainText : root.hints.length) ? root.pal.strong : root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // A thin bar on the right while there's more than fits; drag it or use the wheel.
  Item {
    id: bar
    visible: flick.contentHeight > flick.height + 1
    x: parent.width - width
    y: flick.y
    width: Style.space(8)
    height: flick.height

    Rectangle {
      id: thumb
      width: Style.space(3)
      anchors.horizontalCenter: parent.horizontalCenter
      height: Math.max(Style.space(24), bar.height * flick.visibleArea.heightRatio)
      y: flick.visibleArea.yPosition * bar.height
      radius: width / 2
      color: root.pal.alpha(root.pal.fg, drag.pressed || drag.containsMouse ? 0.5 : 0.28)
    }

    MouseArea {
      id: drag
      anchors.fill: parent
      hoverEnabled: true
      preventStealing: true
      function seek(my) {
        var travel = Math.max(1, bar.height - thumb.height)
        flick.contentY = Math.max(0, Math.min(1, (my - thumb.height / 2) / travel)) * (flick.contentHeight - flick.height)
      }
      onPressed: function(m) { seek(m.y) }
      onPositionChanged: function(m) { if (pressed) seek(m.y) }
    }
  }

  // ---- The buttons, pinned to the foot.
  Item {
    id: actions
    y: parent.height - height
    width: parent.width
    height: Style.space(24)

    Pill {
      visible: root.tab === "explain"
      anchors.left: parent.left
      pal: root.pal
      fontFamily: root.fontFamily
      dense: true
      kind: root.explainText ? "quiet" : "primary"
      label: root.explainText ? "Simpler" : "Explain it"
      tooltip: root.explainText ? "Explain it again, plainer" : ""
      tooltipAbove: true
      busy: root.busy === "explain"
      onClicked: root.explainAsked(!!root.explainText)
    }

    // ‹ 2 / 3 ›
    Row {
      visible: root.tab === "hint" && root.hints.length > 1
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Pill {
        pal: root.pal
        dense: true
        iconOnly: true
        icon: Icons.back
        enabled: root.page > 0
        opacity: enabled ? 1 : 0.35
        onClicked: root.page--
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: (root.hintTotal - root.hints.length + root.page + 1) + " / " + root.hintTotal
        textFormat: Text.PlainText
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Pill {
        pal: root.pal
        dense: true
        iconOnly: true
        icon: Icons.forward
        enabled: root.page < root.hints.length - 1
        opacity: enabled ? 1 : 0.35
        onClicked: root.page++
      }
    }

    Pill {
      visible: root.tab === "hint"
      anchors.right: parent.right
      pal: root.pal
      fontFamily: root.fontFamily
      dense: true
      kind: root.hints.length ? "quiet" : "primary"
      label: root.hints.length ? "More hint" : "Get a hint"
      busy: root.busy === "hint"
      onClicked: root.hintAsked()
    }
  }
}
