import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import "Icons.js" as Icons

// A session as a conversation (Detail's view for Chat sessions): speech
// bubbles with a tail, yours on the right and Claude's on the left, a muted
// line for each tool it used, three dots while it works. live.py `chat`
// reads the transcript and sends messages whole, so nothing here redraws
// per frame: a bubble fades in once when it arrives, the dots step.
//
// The composer is the key window's field drawn by MirrorInput, as in
// LiveTerm; Enter sends the text to the session's hidden terminal. When
// Claude asks something only the terminal can answer (a permission dialog),
// a bar says so and offers the terminal.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property string jobId: ""
  property var keyWindow: null
  readonly property var input: keyWindow ? keyWindow.field : null
  readonly property string inputText: input ? input.text : ""
  // The feed's row (busy, waiting…) and the first prompt of a session still starting.
  property var session: null
  property string pendingText: ""
  property int fontSize: Style.font.subtitle
  property int bubbleSize: Style.font.subtitle
  property bool active: true

  signal grabbed()
  signal showTerminal()
  signal openLink(string url)

  // Markdown text draws its links in the default blue, unreadable on a dark
  // theme and not ours to recolor: they come out of the text (the words stay)
  // and show as chips under the bubble.
  function splitLinks(text) {
    var links = []
    var plain = text.replace(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g, function(all, label, url) {
      links.push({ label: label, url: url })
      return label
    })
    return { text: plain, links: links }
  }

  // A speech tail: a small triangle hanging off a bubble's bottom edge, its
  // point out to the side the speaker is on. Static, drawn once.
  component Tail: Shape {
    id: tail
    property color body: "gray"
    property color outline: "transparent"
    property bool flip: false
    width: Style.space(16)
    height: Style.space(11)
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: tail.body
      strokeColor: tail.outline
      strokeWidth: 1
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      startX: tail.flip ? 0 : tail.width
      startY: -1
      PathLine { x: tail.flip ? tail.width : 0; y: tail.height }
      PathLine { x: tail.flip ? tail.width : 0; y: -1 }
    }
  }

  readonly property string livePath: decodeURIComponent(String(Qt.resolvedUrl("live.py")).replace(/^file:\/\//, ""))
  readonly property var s: session || ({})
  readonly property real gutter: Style.space(14)
  readonly property real maxBubble: Math.max(Style.space(160), (list.width - gutter * 2) * 0.82)

  property bool started: false
  property bool asking: false
  property bool alive: true
  // Sent, and no answer in yet: the dots show even before the feed says busy.
  property double awaitingSince: 0
  readonly property bool working: !root.asking && (root.jobId === "" || !!root.s.busy
                                  || (root.awaitingSince > 0 && Date.now() - root.awaitingSince < 20000))

  implicitHeight: Style.space(440)
  height: implicitHeight

  // ---- Messages

  ListModel { id: messages }

  function indexOfKey(key) {
    for (var i = messages.count - 1; i >= 0; i--) if (messages.get(i).key === key) return i
    return -1
  }

  function indexOfPending(text) {
    for (var i = messages.count - 1; i >= 0; i--) {
      var m = messages.get(i)
      if (m.pending && m.text.trim() === text.trim()) return i
    }
    return -1
  }

  // Whether the bubble before a new one is of another speaker: it gets the tail.
  function roleOf(i) { return i >= 0 && i < messages.count ? messages.get(i).role : "" }

  function add(msg, pending) {
    if (!pending && indexOfKey(msg.key) >= 0) return
    if (msg.role === "user" && !pending) {
      var p = indexOfPending(msg.text)
      if (p >= 0) {
        messages.set(p, { key: msg.key, pending: false })
        return
      }
    }
    if (msg.role !== "user") root.awaitingSince = 0
    var last = messages.count - 1
    if (last >= 0) messages.setProperty(last, "tail", messages.get(last).role !== msg.role || msg.role === "tool")
    messages.append({ key: msg.key, role: msg.role, text: msg.text, pending: !!pending, tail: true })
    if (messages.count > 200) messages.remove(0, messages.count - 200)
  }

  function addPending(text) {
    root.add({ key: "p" + Date.now(), role: "user", text: text }, true)
    root.awaitingSince = Date.now()
    dotsWatch.restart()
  }

  // Past the 20 s grace the dots rest unless the feed says busy.
  Timer {
    id: dotsWatch
    interval: 20500
    onTriggered: root.awaitingSince = 0
  }

  Component.onCompleted: {
    if (root.pendingText !== "") root.addPending(root.pendingText)
    if (keyWindow) keyWindow.handler = root.promptKey
    if (keyWindow) keyWindow.prime()
    Qt.callLater(function() { root.started = true })
  }
  Component.onDestruction: if (keyWindow && keyWindow.handler === root.promptKey) keyWindow.handler = null

  onJobIdChanged: {
    // The session starting gets its id: same conversation. Another one: start over.
    if (started && jobId !== "" && view.wasJob !== "" && view.wasJob !== jobId) {
      started = false
      messages.clear()
      asking = false
      Qt.callLater(function() { root.started = true })
    }
  }

  function send(cmd) {
    if (view.running) view.write(JSON.stringify(cmd) + "\n")
  }

  function submit() {
    var text = root.inputText.trim()
    if (text === "") return
    root.send({ submit: text })
    root.addPending(text)
    root.input.text = ""
    root.stick = true
  }

  // Keys in the composer. Returns true when handled (not typed into the field).
  function promptKey(event) {
    var mods = event.modifiers
    if ((mods & Qt.ControlModifier) && event.key === Qt.Key_C && input && input.selectedText !== "") {
      Quickshell.execDetached(["wl-copy", "--", input.selectedText])
      return true
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(mods & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier))) {
      root.submit()
      return true
    }
    return false
  }

  Process {
    id: view
    property string wasJob: ""
    stdinEnabled: true
    running: root.jobId !== "" && root.started
    command: ["python3", "-I", root.livePath, "chat", root.jobId]
    onRunningChanged: if (running) wasJob = root.jobId
    stdout: SplitParser {
      onRead: function(line) {
        var ev
        try { ev = JSON.parse(line) } catch (e) { return }
        if (ev.history) for (var i = 0; i < ev.history.length; i++) root.add(ev.history[i], false)
        else if (ev.msg) root.add(ev.msg, false)
        else if (ev.state) { root.alive = ev.state.alive !== false; root.asking = ev.state.asking === true }
      }
    }
    onExited: root.alive = false
  }

  Binding { target: root.keyWindow; property: "fieldWidth"; value: composerText.width; when: !!root.keyWindow; restoreMode: Binding.RestoreNone }
  Binding { target: root.keyWindow; property: "fontSize"; value: root.fontSize; when: !!root.keyWindow; restoreMode: Binding.RestoreNone }
  Binding { target: root.keyWindow; property: "fieldWrap"; value: true; when: !!root.keyWindow; restoreMode: Binding.RestoreNone }

  // ---- The conversation

  property bool stick: true

  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: ask.visible ? ask.top : composer.top
    anchors.bottomMargin: Style.space(8)
    clip: true
    model: messages
    spacing: 0
    topMargin: Style.space(12)
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: Style.space(400)
    interactive: false

    onContentHeightChanged: if (root.stick) Qt.callLater(list.positionViewAtEnd)
    onHeightChanged: if (root.stick) Qt.callLater(list.positionViewAtEnd)

    // Scrolling is done here, not by the card's Flickable: it takes the wheel only when there's more.
    footer: Item {
      width: list.width
      height: root.working ? dots.height + Style.space(10) : Style.space(4)

      Rectangle {
        id: dots
        visible: root.working
        x: root.gutter
        y: Style.space(3)
        width: Style.space(54)
        height: Style.space(30)
        radius: Style.space(16)
        color: root.pal.raised
        border.width: 1
        border.color: root.pal.hairline

        property int phase: 0
        Timer {
          interval: 280
          repeat: true
          running: dots.visible && root.active
          onTriggered: dots.phase = (dots.phase + 1) % 4
        }

        Row {
          anchors.centerIn: parent
          spacing: Style.space(6)
          Repeater {
            model: 3
            Rectangle {
              required property int index
              width: Style.space(6)
              height: width
              radius: width / 2
              color: root.pal.muted
              opacity: dots.phase === index ? 1 : 0.35
            }
          }
        }

        Tail {
          x: Style.space(8)
          y: parent.height - 1
          body: dots.color
          outline: dots.border.color
        }
      }
    }

    delegate: Item {
      id: row
      required property int index
      required property string role
      required property string text
      required property bool pending
      required property bool tail

      readonly property var split: role === "assistant" ? root.splitLinks(text) : ({ text: text, links: [] })
      readonly property bool mine: role === "user"
      readonly property bool tool: role === "tool"

      width: list.width
      height: (tool ? chip.height + Style.space(3) : bubble.height + (tail ? Style.space(15) : Style.space(4)))

      // Arrivals fade and rise once; the history on opening just appears.
      property real rise: 0
      opacity: 1
      transform: Translate { y: row.rise }
      Component.onCompleted: if (root.started && root.stick && root.active && root.arrivedLive) enter.start()
      ParallelAnimation {
        id: enter
        NumberAnimation { target: row; property: "opacity"; from: 0; to: 1; duration: 140 }
        NumberAnimation { target: row; property: "rise"; from: Style.space(6); to: 0; duration: 140; easing.type: Easing.OutCubic }
      }

      // A tool call: a muted line, no bubble.
      Row {
        id: chip
        visible: row.tool
        x: root.gutter + Style.space(4)
        height: Style.space(20)
        spacing: Style.space(8)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(5)
          height: width
          radius: width / 2
          color: root.pal.dim
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, root.maxBubble)
          text: row.text
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Rectangle {
        id: bubble
        visible: !row.tool
        x: row.mine ? row.width - width - root.gutter : root.gutter
        width: Math.min(root.maxBubble, body.contentWidth + Style.space(28))
        height: body.contentHeight + Style.space(20) + (chips.visible ? chips.height + Style.space(8) : 0)
        radius: Style.space(16)
        color: row.mine ? root.pal.alpha(root.pal.crab, root.pal.light ? 0.16 : 0.22) : root.pal.raised
        border.width: row.mine ? 0 : 1
        border.color: root.pal.hairline
        opacity: row.pending ? 0.6 : 1

        Text {
          id: body
          x: Style.space(14)
          y: Style.space(10)
          width: root.maxBubble - Style.space(28)
          text: row.split.text
          textFormat: row.mine ? Text.PlainText : Text.MarkdownText
          wrapMode: Text.Wrap
          color: root.pal.fg
          font.family: root.fontFamily
          font.pixelSize: root.bubbleSize
        }

        Flow {
          id: chips
          visible: row.split.links.length > 0
          x: Style.space(14)
          y: body.y + body.contentHeight + Style.space(8)
          width: body.width
          spacing: Style.space(6)

          Repeater {
            model: row.split.links
            Rectangle {
              required property var modelData
              width: Math.min(chips.width, chipText.implicitWidth + Style.space(20))
              height: Style.space(24)
              radius: height / 2
              color: root.pal.alpha(root.pal.crab, hit.containsMouse ? 0.26 : 0.14)

              Text {
                id: chipText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - Style.space(20))
                text: "↗ " + parent.modelData.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.pal.crab
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                id: hit
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openLink(parent.modelData.url)
              }
            }
          }
        }

        Tail {
          visible: row.tail
          flip: row.mine
          x: row.mine ? parent.width - width - Style.space(8) : Style.space(8)
          y: parent.height - 1
          body: parent.color
          outline: row.mine ? "transparent" : root.pal.hairline
        }
      }
    }

    // Mouse wheel scrolls the conversation (the island's Flickable leaves it).
    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2
        list.contentY = Math.max(-list.topMargin, Math.min(list.contentHeight - list.height + list.bottomMargin, list.contentY - dy))
        root.stick = list.atYEnd
      }
    }
  }

  // Bubbles that come from the open view's history don't animate; later ones do.
  property bool arrivedLive: false
  Timer {
    interval: 1200
    running: root.started && root.jobId !== ""
    onTriggered: root.arrivedLive = true
  }
  onStartedChanged: if (!started) arrivedLive = false

  Pill {
    visible: !root.stick && messages.count > 0
    anchors.horizontalCenter: list.horizontalCenter
    anchors.bottom: list.bottom
    anchors.bottomMargin: Style.space(6)
    pal: root.pal
    fontFamily: root.fontFamily
    compact: true
    icon: Icons.forward
    label: "Jump to bottom"
    onClicked: { root.stick = true; list.positionViewAtEnd() }
  }

  // Nothing yet.
  Text {
    visible: messages.count === 0
    anchors.centerIn: list
    text: root.jobId === "" ? "Starting…" : "Say something"
    textFormat: Text.PlainText
    color: root.pal.muted
    font.family: root.fontFamily
    font.pixelSize: root.bubbleSize
  }

  // ---- Claude is asking something only the terminal can answer

  Rectangle {
    id: ask
    visible: root.asking
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: composer.top
    anchors.leftMargin: root.gutter
    anchors.rightMargin: root.gutter
    anchors.bottomMargin: Style.space(8)
    height: Style.space(34)
    radius: Style.space(12)
    color: root.pal.alpha(root.pal.needsYou, 0.14)
    border.width: 1
    border.color: root.pal.alpha(root.pal.needsYou, 0.5)

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "Claude is asking something"
      textFormat: Text.PlainText
      color: root.pal.needsYouText
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Pill {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      pal: root.pal
      fontFamily: root.fontFamily
      compact: true
      icon: Icons.terminal
      label: "Answer in terminal"
      onClicked: root.showTerminal()
    }
  }

  // ---- Composer

  Rectangle {
    id: composer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.gutter
    anchors.rightMargin: root.gutter
    anchors.bottomMargin: Style.space(14)
    height: Math.min(composerText.implicitHeight, composerText.lineStep * 6) + Style.space(22)
    radius: Style.space(18)
    color: root.pal.well
    border.width: 1
    border.color: root.pal.hairline

    Item {
      id: clipBox
      anchors.left: parent.left
      anchors.right: send.left
      anchors.leftMargin: Style.space(16)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      height: parent.height - Style.space(22)
      clip: true

      MirrorInput {
        id: composerText
        readonly property real lineStep: Math.max(1, implicitHeight / Math.max(1, root.inputText.split("\n").length))
        width: parent.width
        y: Math.min(0, parent.height - implicitHeight)
        pal: root.pal
        field: root.input
        fontSize: root.fontSize
        fontFamily: root.fontFamily
        placeholder: "Reply…"
        onFocusRequested: { root.grabbed(); if (root.keyWindow) root.keyWindow.prime() }
      }
    }

    Rectangle {
      id: send
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(30)
      height: width
      radius: width / 2
      readonly property bool ready: root.inputText.trim() !== ""
      color: ready ? root.pal.crab : root.pal.alpha(root.pal.fg, 0.08)

      Icon {
        anchors.centerIn: parent
        d: "M12 19V5M6 11l6-6 6 6"
        size: Style.space(16)
        color: send.ready ? root.pal.onFill(root.pal.crab) : root.pal.muted
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.submit()
      }
    }
  }
}
