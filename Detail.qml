import QtQuick
import Quickshell
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// A background session up close: on the left the crab, its name and folder
// and its step list (its plan, or what it did); on the right its terminal,
// live (LiveTerm, attached through live.py), with a reply field under it.
//
// The terminal hangs on jobId, not on the session row: the feed replaces
// its rows on every change, and a turn ending moves the row between lists,
// which would tear the terminal down and re-attach it each time.
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property string jobId: ""
  // The feed's row for it (or the stand-in while a new one starts).
  property var session: null
  property var keyWindow: null
  property int terminalFontSize: 13
  // A Chat session shows as a conversation (ChatView) rather than the terminal.
  property bool chatStyle: false
  property string pendingPrompt: ""
  // Prompts held by the approval hook (BarWidget.requests): this session's
  // first one is answered here, over the terminal, rather than with its keys.
  property var requests: []
  readonly property var ask: {
    for (var i = 0; i < requests.length; i++)
      if (requests[i].sessionId === s.id) return requests[i]
    return null
  }
  property double now: Date.now()
  property bool active: true
  // The pointer is busy in the terminal (selecting): don't drag-scroll.
  readonly property bool holdsPointer: term.item ? term.item.holdsPointer : false
  // The terminal's file chooser is open: it has the keyboard, the island stays.
  readonly property bool picking: !chatStyle && term.item ? term.item.picking : false

  signal grabbed()
  signal openTerminal()
  signal openEditor(string dir)
  signal newSession(string dir)
  signal openLink(string url)
  signal collapse()
  signal toggleChat()
  signal answered(var request, string choice, var answers)

  readonly property var s: session || ({})
  readonly property bool lively: !!s.busy || !!s.waiting
  // How full the context is, against the auto-compact window.
  readonly property real contextUsed: s.contextWindow > 0 ? Math.min(1, (s.context || 0) / s.contextWindow) : 0

  radius: Style.space(24)
  color: pal.card
  border.width: 1
  border.color: pal.hairline
  // Room for the left column with its buttons under it, and never so short
  // that a fresh session's terminal looks like a slot.
  implicitHeight: Math.max(Style.space(400),
                           side.y + side.implicitHeight + Style.space(24) + actions.implicitHeight + Style.space(22),
                           term.implicitHeight + Style.space(18) * 2,
                           root.ask ? approval.implicitHeight + Style.space(18) * 2 : 0)

  Column {
    id: side
    x: Style.space(26)
    y: Style.space(26)
    width: Style.space(236)
    spacing: Style.space(16)

    // Back to where the detail view was opened from, beside the crab, and
    // the chat/terminal switch on its other side.
    Row {
      spacing: Style.space(12)

      Pill {
        anchors.verticalCenter: parent.verticalCenter
        pal: root.pal
        fontFamily: root.fontFamily
        compact: true
        iconOnly: true
        icon: Icons.back
        tooltip: "Back"
        onClicked: root.collapse()
      }

      Crab {
        pal: root.pal
        unit: Style.spaceReal(5)
        mood: root.s.waiting ? "waiting" : root.s.busy ? (root.s.thinking ? "thinking" : "typing") : "idle"
        color: root.lively ? root.pal.crab : root.pal.idleCrab
        badge: root.s.waiting ? "waiting" : root.s.busy ? "working" : ""
        ring: root.pal.card
        animate: root.active
        fontFamily: root.fontFamily
      }

      Pill {
        anchors.verticalCenter: parent.verticalCenter
        pal: root.pal
        fontFamily: root.fontFamily
        compact: true
        iconOnly: true
        icon: root.chatStyle ? Icons.terminal : Icons.chat
        tooltip: root.chatStyle ? "Show the terminal" : "Show as a conversation"
        onClicked: root.toggleChat()
      }
    }

    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        width: parent.width
        text: root.s.name || ""
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading - 1
        font.bold: true
      }

      Text {
        width: parent.width
        text: (root.chatStyle ? "Chat" : "Claude Code") + " · bg" + (root.s.waiting ? " · needs you" : root.s.busy ? " · " + Format.clock(root.now, root.s.turnStart) : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.s.waiting ? root.pal.needsYouText : root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        text: Format.folder(root.s.workdir || root.s.cwd || "", Quickshell.env("HOME") || "")
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      // Git: the branch, and the worktree when it's a linked one.
      Column {
        visible: !!root.s.git
        z: 1   // the commit's hover label lies over the steps below
        width: parent.width
        spacing: Style.space(3)
        topPadding: Style.space(4)

        // The branch and how old its last commit is; hover for the commit.
        InfoLine {
          z: 1
          icon: Icons.branch
          text: root.s.git ? root.s.git.branch : ""
          note: root.s.git && root.s.git.commitAt ? Format.ago(root.now, root.s.git.commitAt) + " ago" : ""
          tip: root.s.git ? root.s.git.commit || "" : ""
          strong: true
        }

        InfoLine {
          visible: !!root.s.git && root.s.git.worktree !== ""
          icon: Icons.worktree
          // Usually named after its branch, just above: then only the repo.
          text: !root.s.git ? ""
            : root.s.git.worktree === root.s.git.branch ? "worktree of " + root.s.git.repo
            : "worktree " + root.s.git.worktree + " of " + root.s.git.repo
        }
      }

      // Another Code session in the same folder (so the same worktree and branch).
      Item {
        visible: (root.s.workdir || root.s.cwd || "") !== ""
        width: newRow.implicitWidth
        height: newRow.implicitHeight + Style.space(4)

        Rectangle {
          x: -Style.space(6)
          y: Style.space(4) - Style.space(3)
          width: newRow.implicitWidth + Style.space(12)
          height: newRow.implicitHeight + Style.space(6)
          radius: Style.space(6)
          color: root.pal.secondary
          opacity: (newMouse.containsMouse || newHover.hovered) ? 1 : 0
        }

        Row {
          id: newRow
          y: Style.space(4)
          spacing: Style.space(7)

          Icon {
            anchors.verticalCenter: parent.verticalCenter
            d: Icons.plus
            size: Style.space(13)
            stroke: 2.2
            color: (newMouse.containsMouse || newHover.hovered) ? root.pal.crab : root.pal.muted
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "New session here"
            textFormat: Text.PlainText
            color: (newMouse.containsMouse || newHover.hovered) ? root.pal.fg : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        MouseArea {
          id: newMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.newSession(root.s.workdir || root.s.cwd)
        }

        // Passive, so nothing laid over the button can swallow the hover.
        HoverHandler { id: newHover }
      }
    }

    // What it did (or its plan), right under the folder. Kept after the
    // turn ends, so an idle session still shows how its last turn went.
    Column {
      width: parent.width
      spacing: Style.space(9)
      topPadding: Style.space(4)

      Text {
        text: steps.isPlan ? "PLAN" : "ACTIONS"
        textFormat: Text.PlainText
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 0.8
      }

      Steps {
        id: steps
        width: parent.width
        pal: root.pal
        session: root.session
        limit: 6
        now: root.now
        detailLines: 2
        fontSize: Style.font.bodySmall
        fontFamily: root.fontFamily
        filledDone: true
        animate: root.active
      }

      Text {
        visible: steps.items.length === 0
        width: parent.width
        text: root.s.busy ? "Thinking it over…" : "Nothing run yet"
        textFormat: Text.PlainText
        color: root.pal.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

  }

  component InfoLine: Item {
    id: line
    property string icon: ""
    property string text: ""
    property string note: ""   // muted, after the text; the text elides first
    property string tip: ""    // shown under the line on hover
    property bool strong: false
    width: side.width
    implicitHeight: lineRow.implicitHeight

    Row {
      id: lineRow
      width: parent.width
      spacing: Style.space(7)

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        d: line.icon
        size: Style.space(13)
        color: line.strong ? root.pal.crab : root.pal.muted
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, lineRow.width - Style.space(13) - lineRow.spacing
                        - (lineNote.visible ? lineNote.implicitWidth + lineRow.spacing : 0))
        text: line.text
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: line.strong ? root.pal.fg : root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        id: lineNote
        visible: line.note !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: line.note
        textFormat: Text.PlainText
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    MouseArea {
      id: lineHover
      anchors.fill: parent
      enabled: line.tip !== ""
      hoverEnabled: true
    }

    Rectangle {
      visible: line.tip !== "" && lineHover.containsMouse
      y: line.height + Style.space(6)
      width: tipText.width + Style.space(14)
      height: tipText.implicitHeight + Style.space(8)
      radius: Style.space(8)
      color: root.pal.raised
      border.width: 1
      border.color: root.pal.line

      Text {
        id: tipText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, line.width - Style.space(14))
        text: line.tip
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.pal.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // At the foot of the left column: the context meter, then the button.
  Column {
    id: actions
    x: side.x
    width: side.width
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(22)
    spacing: Style.space(6)

    Column {
      visible: (root.s.context || 0) > 0
      width: parent.width
      spacing: Style.space(6)
      bottomPadding: Style.space(10)

      Item {
        width: parent.width
        height: contextLabel.implicitHeight

        Text {
          id: contextLabel
          text: "CONTEXT"
          textFormat: Text.PlainText
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 0.8
        }

        Text {
          anchors.right: parent.right
          text: Math.round(root.contextUsed * 100) + "%"
          textFormat: Text.PlainText
          color: root.contextUsed >= 0.9 ? root.pal.failed : root.contextUsed >= 0.7 ? root.pal.crab : root.pal.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }

      Item {
        width: parent.width
        height: Style.space(4)

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: root.pal.alpha(root.pal.fg, 0.14)
        }

        Rectangle {
          height: parent.height
          width: Math.max(height, parent.width * root.contextUsed)
          radius: height / 2
          color: root.contextUsed >= 0.9 ? root.pal.failed : root.contextUsed >= 0.7 ? root.pal.crab : root.pal.fg
          Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
      }

      Text {
        width: parent.width
        text: Format.tokens(root.s.context, "") + " of " + Format.tokens(root.s.contextWindow, "")
          + (root.contextUsed >= 0.7 ? " · compacts soon" : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Row {
      spacing: Style.space(6)

      Pill {
        pal: root.pal
        fontFamily: root.fontFamily
        compact: true
        icon: Icons.external
        label: "Open in terminal"
        onClicked: root.openTerminal()
      }

      Pill {
        visible: (root.s.workdir || root.s.cwd || "") !== ""
        pal: root.pal
        fontFamily: root.fontFamily
        compact: true
        iconOnly: true
        icon: Icons.code
        tooltip: "Open in VS Code"
        tooltipAbove: true
        onClicked: root.openEditor(root.s.workdir || root.s.cwd)
      }

      Pill {
        visible: !!root.s.git && !!root.s.git.github
        pal: root.pal
        fontFamily: root.fontFamily
        compact: true
        iconOnly: true
        icon: Icons.github
        tooltip: "Open on GitHub"
        tooltipAbove: true
        onClicked: root.openLink(root.s.git.github)
      }
    }
  }

  Loader {
    id: term
    // Up while a new session is still starting too (no job yet): it says so.
    active: root.active
    x: side.x + side.width + Style.space(18)
    y: Style.space(18)
    width: root.width - x - Style.space(18)

    sourceComponent: root.chatStyle ? chatComponent : termComponent
  }

  // The prompt over the terminal (which stays attached underneath): the
  // same card as on Home. "Terminal" hands it back to Claude's own dialog.
  Rectangle {
    visible: !!root.ask
    x: term.x
    y: term.y
    z: 5
    width: term.width
    height: Math.max(term.height, approval.implicitHeight + Style.space(18) * 2)
    radius: Style.space(18)
    color: root.pal.card

    Approval {
      id: approval
      x: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(18) * 2
      pal: root.pal
      fontFamily: root.fontFamily
      request: root.ask
      sessionName: root.s.name || ""
      onAnswered: function(choice, answers) { root.answered(root.ask, choice, answers) }
    }
  }

  Component {
    id: chatComponent

    ChatView {
      jobId: root.jobId
      keyWindow: root.keyWindow
      pal: root.pal
      fontFamily: root.fontFamily
      fontSize: root.terminalFontSize
      session: root.s
      cwd: root.s.workdir || root.s.cwd || ""
      height: root.height - Style.space(18) * 2
      pendingText: root.pendingPrompt
      active: root.active
      onGrabbed: root.grabbed()
      onShowTerminal: root.toggleChat()
      onOpenLink: url => root.openLink(url)
    }
  }

  Component {
    id: termComponent

    LiveTerm {
      jobId: root.jobId
      keyWindow: root.keyWindow
      fontSize: root.terminalFontSize
      title: root.s.name || ""
      model: root.s.model || ""
      effort: root.s.effort || ""
      modelSetting: root.s.modelSetting || ""
      mode: root.s.mode || ""
      cwd: root.s.workdir || root.s.cwd || ""
      pal: root.pal
      fg: root.pal.fg
      mutedFg: root.pal.muted
      accent: root.pal.crab
      showTitle: false
      showWindowChips: false
      status: root.lively ? "live · " + Format.clock(root.now, root.s.turnStart) : "live"
      screenColor: root.pal.light ? root.pal.well : root.pal.mix(root.pal.card, "#000000", 0.35)
      screenRadius: Style.space(18)
      onGrabbed: root.grabbed()
      onOpenTerminal: root.openTerminal()
      onCollapse: root.collapse()
    }
  }
}
