import QtQuick
import qs.Commons

// A permission prompt from approvals.py, as the island's "needs your OK"
// moment: which session wants what, the command, file or URL (and the diff
// for edits), then the buttons Claude Code's own dialog would offer.
// Claude's questions (AskUserQuestion) show their options to pick, and a
// plan waiting to be approved shows the plan. "Terminal" hands the question
// back to the normal prompt; "Open" (background sessions) shows the session
// live in the island without answering.
Column {
  id: root

  property QtObject pal
  property var request: null
  property string sessionName: ""
  property bool background: false
  property int more: 0
  property string fontFamily: Style.font.family

  // answers: for a question, question → the label(s) picked.
  signal answered(string choice, var answers)
  // Open the session in the island, leaving the request waiting.
  signal opened()

  readonly property var diff: request ? (request.diff || []) : []
  readonly property string tool: request ? request.tool || "" : ""
  // What the session line says it wants, in the tool's terms.
  readonly property bool asking: tool === "AskUserQuestion"
  readonly property bool planning: tool === "ExitPlanMode"
  readonly property string wants: asking ? "has a question for you"
    : planning ? "wants to go ahead with its plan"
    : tool === "Bash" ? "wants to run a command"
    : tool === "Edit" || tool === "MultiEdit" ? "wants to edit a file"
    : tool === "Write" ? "wants to write a file"
    : tool === "NotebookEdit" ? "wants to edit a notebook"
    : tool === "WebFetch" ? "wants to fetch a page"
    : tool === "WebSearch" ? "wants to search the web"
    : "wants to use " + (tool.indexOf("mcp__") === 0 ? tool.split("__").pop().replace(/_/g, " ") : tool)
  // Claude's own description of the call; the generic verbs say nothing the line above doesn't.
  readonly property string headline: request && !asking && !planning && !/^(Run a command|Edit a file|Write a file|Edit a notebook|Fetch a page|Search the web|Use .*)$/.test(request.verb || "")
    ? request.verb : ""

  spacing: Style.space(12)

  // Each new request lands with a small pop so it reads as new.
  onRequestChanged: { picks = ({}); if (request) popIn.restart() }

  // ---- A question's picks: question index → labels.
  property var picks: ({})
  readonly property var questions: request && asking ? request.questions || [] : []
  // One question with one answer: picking it is the answer.
  readonly property bool instant: questions.length === 1 && !questions[0].multiSelect
  readonly property bool complete: questions.length > 0 && questions.every(function(q, i) { return (picks[i] || []).length > 0 })

  function pick(i, label) {
    var next = {}
    for (var k in picks) next[k] = picks[k]
    var now = (next[i] || []).slice()
    var at = now.indexOf(label)
    if (questions[i].multiSelect) { if (at >= 0) now.splice(at, 1); else now.push(label) }
    else now = [label]
    next[i] = now
    picks = next
    if (instant) submit()
  }

  function submit() {
    var out = {}
    for (var i = 0; i < questions.length; i++) out[questions[i].question] = (picks[i] || []).join(", ")
    root.answered("answer", out)
  }
  NumberAnimation {
    id: popIn
    target: root
    property: "scale"
    from: 0.97
    to: 1
    duration: 260
    easing.type: Easing.OutBack
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    Rectangle {
      id: dot
      width: Style.space(8)
      height: width
      radius: width / 2
      anchors.verticalCenter: parent.verticalCenter
      color: root.pal.needsYou
      SequentialAnimation on opacity {
        running: root.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 420; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 420; easing.type: Easing.InOutSine }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, root.width * 0.4)
      text: root.sessionName
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.strong
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Chip {
      visible: root.background
      anchors.verticalCenter: parent.verticalCenter
      pal: root.pal
      label: "bg"
      fontFamily: root.fontFamily
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, root.width - x)
      text: root.wants
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Text {
    visible: root.headline !== ""
    width: parent.width
    text: root.headline
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    maximumLineCount: 2
    elide: Text.ElideRight
    color: root.pal.strong
    font.family: root.fontFamily
    font.pixelSize: Style.font.heading
    font.bold: true
  }

  // ---- The questions, each with its options.
  Repeater {
    model: root.questions

    Column {
      id: question
      required property var modelData
      required property int index
      width: root.width
      spacing: Style.space(8)

      // A long question steps down a size, then another, rather than being cut off.
      readonly property string text: modelData.question + (modelData.multiSelect ? "  (pick any)" : "")
      readonly property int fullSize: root.questions.length > 1 ? Style.font.subtitle : Style.font.heading
      readonly property int fitSize: atFull.lineCount <= 3 ? fullSize
        : atSubtitle.lineCount <= 3 ? Style.font.subtitle : Style.font.body

      Text {
        id: atFull
        visible: false
        width: questionText.width
        text: question.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: question.fullSize
        font.bold: true
      }

      Text {
        id: atSubtitle
        visible: false
        width: questionText.width
        text: question.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Chip {
          visible: question.modelData.header !== ""
          anchors.verticalCenter: parent.verticalCenter
          pal: root.pal
          label: question.modelData.header
          fontFamily: root.fontFamily
        }

        Text {
          id: questionText
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - x
          text: question.text
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          maximumLineCount: question.fitSize === Style.font.body ? 5 : 3
          elide: Text.ElideRight
          color: root.pal.strong
          font.family: root.fontFamily
          font.pixelSize: question.fitSize
          font.bold: true
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: question.modelData.options

          Rectangle {
            id: option
            required property var modelData
            required property int index
            readonly property bool picked: (root.picks[question.index] || []).indexOf(modelData.label) >= 0
            width: Math.min(Math.max(optionLabel.implicitWidth, Math.min(optionNote.implicitWidth, Style.space(240))) + Style.space(14) * 2,
                            (question.width - Style.space(6)) / 2)
            height: optionColumn.implicitHeight + Style.space(9) * 2
            radius: Style.space(14)
            color: picked ? root.pal.alpha(root.pal.needsYou, 0.16)
              : optionMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.10) : root.pal.alpha(root.pal.fg, 0.05)
            border.width: 1
            border.color: picked ? root.pal.alpha(root.pal.needsYou, 0.7) : root.pal.alpha(root.pal.fg, optionMouse.containsMouse ? 0.22 : 0.10)
            Behavior on color { ColorAnimation { duration: 100 } }

            Column {
              id: optionColumn
              x: Style.space(14)
              y: Style.space(9)
              width: parent.width - Style.space(14) * 2
              spacing: Style.space(2)

              Text {
                id: optionLabel
                width: Math.min(implicitWidth, parent.width)
                text: (option.index + 1) + ". " + option.modelData.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.pal.strong
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }

              Text {
                id: optionNote
                visible: text !== ""
                width: parent.width
                text: option.modelData.description
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: root.pal.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: optionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.pick(question.index, option.modelData.label)
            }
          }
        }
      }
    }
  }

  // ---- The plan, for a plan waiting to be approved.
  Rectangle {
    visible: root.planning && !!root.request && (root.request.plan || "") !== ""
    width: parent.width
    height: Math.min(planText.implicitHeight, Style.space(180)) + Style.space(12) * 2
    radius: Style.space(12)
    color: root.pal.well
    border.width: 1
    border.color: root.pal.alpha(root.pal.fg, 0.10)
    clip: true

    Text {
      id: planText
      x: Style.space(14)
      y: Style.space(12)
      width: parent.width - Style.space(14) * 2
      height: Math.min(implicitHeight, Style.space(180))
      text: root.request ? root.request.plan || "" : ""
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      elide: Text.ElideRight
      color: root.pal.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      lineHeight: 1.1
    }
  }

  // The command, file or URL, then the diff for edits.
  Rectangle {
    visible: !!root.request && (root.request.detail !== "" || root.diff.length > 0)
    width: root.diff.length > 0 ? parent.width : Math.min(parent.width, detailText.implicitWidth + Style.space(14) * 2)
    height: detailColumn.implicitHeight + Style.space(10) * 2
    radius: Style.space(12)
    color: root.pal.well
    border.width: 1
    border.color: root.pal.alpha(root.pal.fg, 0.10)

    Column {
      id: detailColumn
      x: Style.space(14)
      y: Style.space(10)
      width: parent.width - Style.space(14) * 2
      spacing: Style.space(4)

      Text {
        id: detailText
        visible: text !== ""
        width: Math.min(implicitWidth, root.width - Style.space(14) * 2)
        text: root.request ? root.request.detail : ""
        textFormat: Text.PlainText
        wrapMode: Text.WrapAnywhere
        maximumLineCount: 5
        elide: Text.ElideRight
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      Repeater {
        model: root.diff
        Rectangle {
          required property string modelData
          readonly property bool added: modelData.charAt(0) === "+"
          readonly property color tone: added ? root.pal.done : root.pal.failed
          width: detailColumn.width
          height: diffLine.implicitHeight + 2
          radius: 3
          color: root.pal.alpha(tone, 0.14)
          Text {
            id: diffLine
            x: Style.space(4)
            width: parent.width - x * 2
            anchors.verticalCenter: parent.verticalCenter
            text: modelData
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.pal.light ? Qt.darker(parent.tone, 1.3) : Qt.lighter(parent.tone, 1.35)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  Item {
    width: parent.width
    height: buttons.implicitHeight

    Row {
      id: buttons
      visible: !root.asking
      spacing: Style.space(8)
      Pill { pal: root.pal; fontFamily: root.fontFamily; label: root.planning ? "Keep planning" : "Deny"; onClicked: root.answered("deny", null) }
      Pill {
        visible: !!root.request && root.request.alwaysLabel !== ""
        pal: root.pal
        fontFamily: root.fontFamily
        label: root.request ? root.request.alwaysLabel : ""
        onClicked: root.answered("always", null)
      }
      Pill { pal: root.pal; fontFamily: root.fontFamily; label: root.planning ? "Approve plan" : "Allow"; kind: "primary"; onClicked: root.answered("allow", null) }
    }

    // Several questions, or several picks: send them together.
    Pill {
      visible: root.asking && !root.instant
      pal: root.pal
      fontFamily: root.fontFamily
      label: "Send answers"
      kind: root.complete ? "primary" : "secondary"
      opacity: root.complete ? 1 : 0.5
      onClicked: if (root.complete) root.submit()
    }

    Row {
      anchors.right: parent.right
      spacing: Style.space(4)

      Pill {
        visible: root.background
        pal: root.pal
        fontFamily: root.fontFamily
        label: "Open"
        kind: "quiet"
        onClicked: root.opened()
      }

      Pill {
        pal: root.pal
        fontFamily: root.fontFamily
        label: "Terminal"
        kind: "quiet"
        onClicked: root.answered("terminal", null)
      }
    }
  }

  Text {
    visible: root.more > 0
    text: "+" + root.more + " more waiting"
    textFormat: Text.PlainText
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
