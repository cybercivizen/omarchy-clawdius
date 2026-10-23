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
  // Pasted images waiting to go with the next message (paths).
  property var images: []
  property int fontSize: Style.font.subtitle
  property int bubbleSize: Style.font.subtitle
  property bool active: true
  // The session's folder: linked paths inside it are written relative to it.
  property string cwd: ""

  // The card's Flickable stays still while the pointer is over the
  // conversation, so a drag there selects text instead of scrolling the card.
  readonly property bool holdsPointer: hover.hovered

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

  // A speech bubble drawn as one outline: the rounded rectangle, with the
  // corner on the speaker's side running straight down into a tail that points
  // out and back, so there's no seam where tail meets bubble. The tail hangs
  // below the w x h body. Static: rebuilt only when the size changes.
  component Bubble: Shape {
    id: bub
    property real w: 0
    property real h: 0
    property string tail: ""   // "", "left" or "right"
    property color fill: "gray"
    property color outline: "transparent"
    readonly property real r: Style.space(16)
    readonly property real tailW: Style.space(14)
    readonly property real tailH: Style.space(10)
    // Inset half a pixel so the one-pixel outline lands on whole pixels.
    readonly property string d: {
      var l = 0.5, t = 0.5, rt = w - 0.5, bt = h - 0.5, r = bub.r
      var arc = " A" + r + "," + r + " 0 0 1 "
      var s = "M" + (l + r) + "," + t + " H" + (rt - r) + arc + rt + "," + (t + r)
      if (tail === "right") s += " V" + (bt + tailH) + " L" + (rt - tailW) + "," + bt
      else s += " V" + (bt - r) + arc + (rt - r) + "," + bt
      s += " H" + (tail === "left" ? l + tailW : l + r)
      if (tail === "left") s += " L" + l + "," + (bt + tailH)
      else s += arc + l + "," + (bt - r)
      return s + " V" + (t + r) + arc + (l + r) + "," + t + " Z"
    }
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: bub.fill
      strokeColor: bub.outline
      strokeWidth: bub.outline.a > 0 ? 1 : -1
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: bub.d }
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

  // Detail sizes it to the card, so the composer sits at the bottom.
  implicitHeight: Style.space(440)

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
    if (text === "" && root.images.length === 0) return
    var shown = text !== "" ? text : (root.images.length > 1 ? root.images.length + " images" : "Image")
    root.send({ images: root.images, submit: text !== "" ? text : " " })
    root.addPending(shown)
    root.images = []
    root.input.text = ""
    root.stick = true
  }

  // The bubble text last selected: starting another clears it.
  property Item selecting: null
  property Item wasSelecting: null
  onSelectingChanged: {
    if (wasSelecting && wasSelecting !== selecting) wasSelecting.deselect()
    wasSelecting = selecting
  }

  function copySelection(edit) {
    var text = edit.selectedText.replace(/[\u2028\u2029]/g, "\n").replace(/\u00a0/g, " ")
    if (text.trim() !== "") Quickshell.execDetached(["wl-copy", "--", text])
  }

  // ---- Linking files and folders, as in LiveTerm: typed into the composer as @path

  readonly property string home: Quickshell.env("HOME") || ""
  property bool linkMenu: false
  readonly property bool picking: browser.running

  Process {
    id: browser
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.mention(text.split("\n"))
    }
  }

  function browse(kind) {
    if (browser.running) return
    browser.command = ["zenity", "--file-selection", "--filename=" + (root.cwd || root.home) + "/",
                       "--title=" + (kind === "folder" ? "Link a folder" : "Link files")]
      .concat(kind === "folder" ? ["--directory"] : ["--multiple", "--separator=\n"])
    browser.running = true
  }

  // Inside the session's folder relative, else absolute; quoted if it has spaces.
  function mention(paths) {
    var refs = []
    for (var i = 0; i < paths.length; i++) {
      var path = paths[i]
      if (!path) continue
      if (root.cwd && path === root.cwd) path = "."
      else if (root.cwd && path.indexOf(root.cwd + "/") === 0) path = path.slice(root.cwd.length + 1)
      refs.push(/\s/.test(path) ? '@"' + path + '"' : "@" + path)
    }
    if (!refs.length || !input) return
    var at = input.cursorPosition
    var before = input.text.slice(0, at)
    var add = (before && !/\s$/.test(before) ? " " : "") + refs.join(" ") + " "
    input.text = before + add + input.text.slice(at)
    input.cursorPosition = at + add.length
    if (keyWindow) keyWindow.prime()
  }

  // Where each @path in the composer starts and ends.
  readonly property var links: {
    var found = [], re = /(^|\s)(@"[^"]+"|@\S+)/g, m
    while ((m = re.exec(inputText)) !== null) {
      var start = m.index + m[1].length
      found.push({ start: start, end: start + m[2].length })
    }
    return found
  }

  // Keys in the composer. Returns true when handled (not typed into the field).
  function promptKey(event) {
    var mods = event.modifiers
    // An image on the clipboard joins the message; text still pastes here as usual.
    if ((mods & Qt.ControlModifier) && event.key === Qt.Key_V) { root.send({ grab: true }); return false }
    if (event.key === Qt.Key_Backspace && root.inputText === "" && root.images.length > 0) {
      root.images = root.images.slice(0, -1)
      return true
    }
    // Backspace at (or inside) an @path takes the whole link off, and the space after it.
    if (event.key === Qt.Key_Backspace && !(mods & (Qt.ControlModifier | Qt.AltModifier)) && input && input.selectedText === "") {
      var at = input.cursorPosition, t = root.inputText
      for (var i = 0; i < root.links.length; i++) {
        var l = root.links[i]
        if (at > l.start && at <= l.end + (t.charAt(l.end) === " " ? 1 : 0)) {
          input.text = t.slice(0, l.start) + t.slice(Math.max(at, l.end))
          input.cursorPosition = l.start
          return true
        }
      }
    }
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
        else if (ev.image) root.images = root.images.concat([ev.image])
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

  Flickable {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: ask.visible ? ask.top : composer.top
    anchors.bottomMargin: Style.space(8)
    clip: true
    contentWidth: width
    contentHeight: rows.height
    boundsBehavior: Flickable.StopAtBounds
    interactive: false

    readonly property real maxY: Math.max(0, contentHeight - height)
    function scrollToEnd() { contentY = maxY }
    onContentHeightChanged: if (root.stick) Qt.callLater(list.scrollToEnd)
    onHeightChanged: if (root.stick) Qt.callLater(list.scrollToEnd)

    Column {
      id: rows
      width: list.width
      topPadding: Style.space(12)

      Repeater {
        model: messages

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
            color: "transparent"
            opacity: row.pending ? 0.6 : 1

            Bubble {
              w: bubble.width
              h: bubble.height
              tail: row.tail ? (row.mine ? "right" : "left") : ""
              fill: row.mine ? root.pal.alpha(root.pal.crab, root.pal.light ? 0.16 : 0.22) : root.pal.raised
              outline: row.mine ? "transparent" : root.pal.hairline
            }

            TextEdit {
              id: body
              x: Style.space(14)
              y: Style.space(10)
              width: root.maxBubble - Style.space(28)
              text: row.split.text
              textFormat: row.mine ? TextEdit.PlainText : TextEdit.MarkdownText
              wrapMode: TextEdit.Wrap
              readOnly: true
              selectByMouse: true
              activeFocusOnPress: false
              color: root.pal.fg
              selectionColor: root.pal.alpha(root.pal.crab, 0.4)
              selectedTextColor: root.pal.fg
              font.family: root.fontFamily
              font.pixelSize: root.bubbleSize
              onSelectedTextChanged: if (selectedText !== "") root.selecting = body
              // A drag ends: the selection is copied, as in the terminal.
              HoverHandler { cursorShape: Qt.IBeamCursor }
              TapHandler {
                acceptedButtons: Qt.LeftButton
                onPressedChanged: if (!pressed) root.copySelection(body)
              }
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
          }
        }
      }

        Item {
          width: list.width
          height: root.working ? dots.height + Style.space(10) : Style.space(4)

          Rectangle {
            id: dots
            visible: root.working
            x: root.gutter
            y: Style.space(3)
            width: Style.space(54)
            height: Style.space(30)
            color: "transparent"

            property int phase: 0
            Timer {
              interval: 280
              repeat: true
              running: dots.visible && root.active
              onTriggered: dots.phase = (dots.phase + 1) % 4
            }

            Bubble {
              w: dots.width
              h: dots.height
              tail: "left"
              fill: root.pal.raised
              outline: root.pal.hairline
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

          }
        }
    }

    HoverHandler { id: hover }

    // Mouse wheel scrolls the conversation (the island's Flickable leaves it).
    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        // Quicker than 1:1: a wheel notch (120) moves about 144 px.
        var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y * 2 : event.angleDelta.y * 1.2
        list.contentY = Math.max(0, Math.min(list.maxY, list.contentY - dy))
        root.stick = list.contentY >= list.maxY - 1
      }
    }
  }

  // A scroll bar along the conversation's right edge: drag the thumb, or click
  // the track to jump there. Only while there's more than fits.
  Item {
    id: bar
    visible: list.maxY > 0
    anchors.right: list.right
    anchors.top: list.top
    anchors.bottom: list.bottom
    anchors.topMargin: Style.space(6)
    anchors.bottomMargin: Style.space(6)
    width: Style.space(12)

    readonly property real thumbH: Math.max(Style.space(28), height * list.height / Math.max(1, list.contentHeight))
    readonly property real travel: Math.max(1, height - thumbH)

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: barMouse.containsMouse || barMouse.pressed ? Style.space(6) : Style.space(4)
      height: bar.thumbH
      y: list.maxY > 0 ? list.contentY / list.maxY * bar.travel : 0
      radius: width / 2
      color: root.pal.alpha(root.pal.fg, barMouse.containsMouse || barMouse.pressed ? 0.4 : 0.22)
    }

    MouseArea {
      id: barMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      function scrollTo(y) {
        list.contentY = Math.max(0, Math.min(list.maxY, (y - bar.thumbH / 2) / bar.travel * list.maxY))
        root.stick = list.contentY >= list.maxY - 1
      }
      onPressed: function(mouse) { scrollTo(mouse.y) }
      onPositionChanged: function(mouse) { if (pressed) scrollTo(mouse.y) }
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
    onClicked: { root.stick = true; list.scrollToEnd() }
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

  // What to link: a menu rising from the paperclip, over the conversation.
  PickMenu {
    visible: root.linkMenu
    z: 10
    x: Math.max(0, composer.x + attach.x + attach.width - width)
    y: composer.y - height - Style.space(6)
    title: "Link"
    options: [{ id: "files", label: "Files…" }, { id: "folder", label: "Folder…" }]
    ink: root.pal.fg
    quietInk: root.pal.muted
    hot: root.pal.crab
    fill: root.pal.raised
    onPicked: function(id) { root.linkMenu = false; root.browse(id) }
  }

  // ---- Composer

  Rectangle {
    id: composer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: root.gutter
    anchors.rightMargin: root.gutter
    anchors.bottomMargin: Style.space(4)
    height: Math.min(composerText.implicitHeight, composerText.lineStep * 6) + Style.space(22) + thumbs.height
    radius: Style.space(18)
    color: root.pal.well
    border.width: 1
    border.color: root.pal.hairline

    // Pasted images, as small thumbnails with a way to take each back off.
    Flow {
      id: thumbs
      x: Style.space(14)
      y: Style.space(8)
      width: parent.width - x * 2
      height: root.images.length > 0 ? Style.space(52) : 0
      spacing: Style.space(6)

      Repeater {
        model: root.images

        Item {
          id: thumb
          required property int index
          required property string modelData
          width: Style.space(48)
          height: Style.space(48)

          Image {
            anchors.fill: parent
            source: "file://" + thumb.modelData
            sourceSize.width: Style.space(96)
            sourceSize.height: Style.space(96)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }

          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            width: Style.space(16)
            height: width
            radius: width / 2
            color: root.pal.card
            border.width: 1
            border.color: root.pal.hairline

            Text {
              anchors.centerIn: parent
              text: "×"
              textFormat: Text.PlainText
              color: root.pal.fg
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.images = root.images.filter(function(p, i) { return i !== thumb.index })
            }
          }
        }
      }
    }

    Item {
      id: clipBox
      anchors.left: parent.left
      anchors.right: attach.left
      anchors.leftMargin: Style.space(16)
      anchors.rightMargin: Style.space(8)
      anchors.top: parent.top
      anchors.topMargin: Style.space(11) + thumbs.height
      height: parent.height - Style.space(22) - thumbs.height
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
        onFocusRequested: { root.linkMenu = false; root.grabbed(); if (root.keyWindow) root.keyWindow.prime() }
      }
    }

    // Link files or a folder: the chooser, from the choices above the composer.
    Rectangle {
      id: attach
      anchors.right: send.left
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: width
      radius: width / 2
      color: root.linkMenu || root.picking ? root.pal.alpha(root.pal.fg, 0.14)
        : attachMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.08) : "transparent"

      Icon {
        anchors.centerIn: parent
        d: Icons.clip
        size: Style.space(15)
        stroke: 2
        color: attachMouse.containsMouse || root.linkMenu ? root.pal.fg : root.pal.muted
      }

      MouseArea {
        id: attachMouse
        anchors.fill: parent
        enabled: !root.picking
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { root.linkMenu = !root.linkMenu; if (root.keyWindow) root.keyWindow.prime() }
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
      readonly property bool ready: root.inputText.trim() !== "" || root.images.length > 0
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
