import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Icons.js" as Icons

// A background session's terminal, live inside the card. live.py runs
// `claude attach` in a hidden tmux pane and streams its screen.
//
// The prompt is drawn here, so typing never waits on the terminal: the text
// goes over in one piece on Enter. The card can't take the keyboard (see
// KeyWindow.qml), so the real text field lives on that window and this
// draws its text and caret. When Claude's own prompt isn't the thing
// on screen (a permission dialog, a question) and ours is empty, keys go
// straight to the terminal instead, so it can be answered. Text that turns
// up in Claude's own box (a prompt given back after an interrupt) moves
// over to ours, so its box never shows. Text half typed here stays here,
// so a dialog that pops up mid-sentence can't catch a stray key.
//
// Destroying this (collapsing the row) only detaches: the session carries on.
Column {
  id: root

  property string jobId: ""
  property var keyWindow: null
  readonly property var input: keyWindow ? keyWindow.field : null
  readonly property string inputText: input ? input.text : ""
  property string title: ""
  // From the feed (the transcript): used until the screen says otherwise.
  property string model: ""
  property string effort: ""
  property string mode: ""
  // The alias it runs under ("opusplan", "sonnet", …), also from the feed.
  property string modelSetting: ""
  property string cwd: ""
  property color fg: Color.foreground
  property color mutedFg: Qt.darker(fg, 1.45)
  property color accent: "#D97757"
  property int rows: 26
  property int fontSize: Style.font.subtitle
  // The island's detail view shows the name, "Open in terminal" and
  // "Collapse" beside the terminal, and a status line here instead.
  property bool showTitle: true
  property bool showWindowChips: true
  property string status: ""
  property color screenColor: Qt.rgba(0, 0, 0, 0.72)
  property real screenRadius: Style.space(10)

  // Wants the card pinned so it keeps keyboard focus; asks for a real window.
  signal grabbed()
  signal openTerminal()
  signal collapse()

  readonly property string livePath: decodeURIComponent(String(Qt.resolvedUrl("live.py")).replace(/^file:\/\//, ""))
  readonly property int cols: Math.max(40, Math.floor((screenBox.width - pad * 2) / metrics.averageCharacterWidth))
  readonly property real pad: Style.space(14)
  property string page: ""
  // A frame came in; an empty page then means no conversation yet, not attaching.
  property bool framed: false
  property bool alive: true
  // Claude's prompt is empty and cut out of the picture (live.py).
  property bool promptReady: false
  // Images pasted into Claude's box ("[Image #1]"), shown as chips.
  property var attachments: []
  // Claude's predicted next prompt (its gray text in that empty prompt):
  // drawn in ours while it's empty, and Tab takes it.
  property string suggestion: ""
  readonly property bool suggesting: alive && promptReady && !rawKeys && suggestion !== ""
    && attachments.length === 0 && inputText === ""
  // Text in Claude's own box that we didn't put there (live.py): taken over.
  property string draft: ""
  // (Not before the first frame: a session still starting isn't asking anything.)
  readonly property bool rawWanted: framed && !promptReady && draft === "" && inputText === ""
  // Only once that has held a moment: Claude draws its prompt box over a
  // frame or two (at start, and after a send), and in between it isn't
  // there, which would flash the amber "Claude is asking" for a split second.
  property bool rawKeys: false
  onRawWantedChanged: {
    if (rawWanted) rawDelay.restart()
    else { rawDelay.stop(); rawKeys = false }
  }
  Timer {
    id: rawDelay
    interval: 350
    onTriggered: root.rawKeys = root.rawWanted
  }
  // What the cut-off banner and mode line showed, fresher than the feed.
  property string screenModel: ""
  property string screenMode: ""
  property string screenEffort: ""
  // Scrolled up in the conversation: the card shows "Jump to bottom".
  property bool scrolled: false
  // Messages that arrived while scrolled up (Claude's own pill counts them).
  property int unread: 0

  // claude-opus-5-5 → Opus 5.5
  function modelName(id) {
    var m = /^claude-([a-z]+)-(\d+)(?:-(\d+))?/.exec(id || "")
    if (!m) return id || ""
    return m[1].charAt(0).toUpperCase() + m[1].slice(1) + " " + m[2] + (m[3] && m[3].length < 3 ? "." + m[3] : "")
  }

  // Screen ("auto", "plan", "accept edits") or transcript ("acceptEdits") → label.
  function modeName(mode) {
    var key = String(mode || "").replace(/\s+/g, "").toLowerCase()
    var names = { auto: "Auto mode", plan: "Plan mode", acceptedits: "Accept edits", bypasspermissions: "Bypass permissions",
                  bypass: "Bypass permissions", default: "Ask before edits", dontask: "Don't ask" }
    return names[key] || (mode ? String(mode) : "")
  }

  // xhigh → Extra high
  function effortName(e) {
    e = String(e || "")
    return e === "xhigh" ? "Extra high" : e ? e.charAt(0).toUpperCase() + e.slice(1) : ""
  }

  // opusplan: Opus while in plan mode, Sonnet otherwise. The banner calls it "Opus Plan".
  readonly property bool opusPlan: modelSetting !== "" ? /^opusplan/i.test(modelSetting) : /^Opus (Plan|in plan mode)/.test(screenModel)
  // The model answering: the transcript's is per turn, the banner's is the start's.
  readonly property string liveModel: modelName(root.model) || (/^Opus (Plan|in plan mode)/.test(root.screenModel) ? "" : root.screenModel)
  readonly property bool planning: String(root.screenMode || root.mode).replace(/\s+/g, "").toLowerCase() === "plan"
  // On opusplan, the half in use follows the mode at once (not a reply later),
  // with the transcript's version once a reply of that family is in.
  readonly property string modelLabel: {
    if (!opusPlan) return liveModel
    var family = planning ? "Opus" : "Sonnet"
    return "Opus Plan · " + (liveModel.indexOf(family) === 0 ? liveModel : family)
  }
  readonly property string modeLabel: modeName(root.screenMode || root.mode)
  // The transcript's follows /effort; the banner's is the start's.
  readonly property string currentEffort: String(root.effort || root.screenEffort || "").toLowerCase()
  readonly property string effortLabel: currentEffort ? effortName(currentEffort) + " effort" : ""
  readonly property string currentModel: opusPlan ? "opusplan" : ((/^[A-Za-z]+/.exec(liveModel) || [""])[0]).toLowerCase()

  // The row of choices open under the composer: "model", "effort", "attach" or "".
  property string picker: ""
  // Model and effort change through Claude's own /model and /effort, so only
  // while its prompt is up and empty, and ours is too.
  readonly property bool canCommand: alive && promptReady && !rawKeys && inputText === "" && attachments.length === 0
  onCanCommandChanged: if (!canCommand && picker !== "attach") picker = ""
  readonly property var pickerOptions: picker === "model" ? [
      { id: "opus", label: "Opus" }, { id: "sonnet", label: "Sonnet" }, { id: "haiku", label: "Haiku" },
      { id: "fable", label: "Fable" }, { id: "opusplan", label: "Opus Plan", special: true } ]
    : picker === "effort" ? ["low", "medium", "high", "xhigh", "max"].map(function(e) {
        return root.pal ? { id: e, label: effortName(e), tone: root.pal.effort(e) } : { id: e, label: effortName(e) } })
    : picker === "attach" ? [{ id: "files", label: "Files…" }, { id: "folder", label: "Folder…" }]
    : []
  readonly property string pickerCurrent: picker === "model" ? currentModel : picker === "effort" ? currentEffort : ""

  // What the open menu rises from: the chip or the paperclip.
  property Item pickerAnchor: null

  function togglePicker(which, anchor) {
    var opening = root.picker !== which
    root.focusInput()   // closes the one open
    if (opening) { root.pickerAnchor = anchor; root.picker = which }
  }

  function pick(id) {
    var which = root.picker
    root.picker = ""
    if (which === "attach") root.browse(id)
    else if (root.canCommand) root.send({ submit: "/" + which + " " + id })
    root.focusInput()
  }

  // Files or a folder to point Claude at, from the desktop's file chooser:
  // typed into our prompt as @path, as Claude's own @ completion would.
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
  }
  readonly property string home: Quickshell.env("HOME") || ""
  // The @path links typed into the composer (as mention() writes them), for
  // drawing them as chips: where each starts and ends, and its full path.
  readonly property var links: {
    var found = [], re = /(^|\s)(@"[^"]+"|@\S+)/g, m
    while ((m = re.exec(inputText)) !== null) {
      var start = m.index + m[1].length, ref = m[2]
      found.push({ start: start, end: start + ref.length, path: fullPath(ref.slice(1).replace(/^"|"$/g, "")) })
    }
    return found
  }
  function fullPath(path) {
    var full = path === "." ? cwd : path.charAt(0) === "/" || !cwd ? path : cwd + "/" + path
    return home && full.indexOf(home) === 0 ? "~" + full.slice(home.length) : full
  }
  readonly property string cwdLabel: home && cwd.indexOf(home) === 0 ? "~" + cwd.slice(home.length) : cwd
  property bool started: false

  spacing: Style.space(10)

  FontMetrics {
    id: metrics
    font.family: "monospace"
    font.pixelSize: root.fontSize
  }

  // A line of the page as it's really laid out: rich text rounds each line
  // to whole pixels (13px: 18, where lineSpacing says 17.14), so `rows` of
  // lineSpacing came up short and pushed the conversation's first lines out
  // the top.
  TextEdit {
    id: lineProbe
    visible: false
    textFormat: TextEdit.RichText
    font.family: "monospace"
    font.pixelSize: root.fontSize
    text: '<p style="margin:0;white-space:pre">x</p><p style="margin:0;white-space:pre">x</p>'
  }
  readonly property real lineHeight: lineProbe.implicitHeight > 0 ? lineProbe.implicitHeight / 2 : metrics.lineSpacing

  function send(cmd) {
    if (view.running) view.write(JSON.stringify(cmd) + "\n")
  }

  // The wheel, in Claude's own lines: a touchpad scrolls one for each line
  // height swiped, a mouse wheel three a notch. Turning back starts afresh.
  property real wheelLines: 0
  function scrollBy(wheel) {
    var lines = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y / root.lineHeight : wheel.angleDelta.y / 40
    if (lines * root.wheelLines < 0) root.wheelLines = 0
    root.wheelLines += lines
    var steps = root.wheelLines > 0 ? Math.floor(root.wheelLines) : Math.ceil(root.wheelLines)
    if (steps === 0) return
    root.wheelLines -= steps
    root.send({ wheel: steps })
  }

  // ---- Up / Down: the prompts given in this folder (live.py history), in
  //      our prompt, never Claude's. Up on the first line goes back, Down on
  //      the last forward, and past the newest is what was being typed.
  property var history: []
  property int historyAt: -1
  property string historyDraft: ""
  property bool recalling: false

  Process {
    id: historyProcess
    command: ["python3", "-I", root.livePath, "history", root.cwd || "."]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.history = JSON.parse(text) } catch (e) { root.history = [] }
      }
    }
  }
  function loadHistory() { if (root.cwd && !historyProcess.running) historyProcess.running = true }
  onCwdChanged: loadHistory()

  function recall(at) {
    if (at < -1 || at >= root.history.length) return
    if (root.historyAt === -1) root.historyDraft = input.text
    root.historyAt = at
    root.recalling = true
    input.text = at === -1 ? root.historyDraft : root.history[at]
    input.cursorPosition = input.text.length
    root.recalling = false
  }

  Connections {
    target: root.input
    function onTextChanged() { if (!root.recalling) root.historyAt = -1 }
  }

  // Claude's box held its text a moment (not our own paste on its way to
  // Enter): ours takes it, and Claude's is emptied.
  property double submittedAt: 0
  Timer {
    id: adoptDelay
    interval: 600
    onTriggered: root.adoptDraft()
  }
  onDraftChanged: if (draft !== "") adoptDelay.restart(); else adoptDelay.stop()
  function adoptDraft() {
    var text = root.draft
    if (!text || !input || Date.now() - root.submittedAt < 2500) return
    root.recalling = true
    input.text = input.text ? text + "\n" + input.text : text
    input.cursorPosition = input.text.length
    root.recalling = false
    root.send({ clear: text.length + 40 })
  }

  function submit() {
    var text = root.inputText
    if (text.trim() === "") {
      if (root.attachments.length) root.send({ keys: ["Enter"] })   // just the images
      return
    }
    // After an [Image #n] in Claude's box, the text needs a space before it.
    root.send({ submit: (root.attachments.length ? " " : "") + text })
    root.submittedAt = Date.now()
    input.text = ""
    root.historyAt = -1
    root.history = [text].concat(root.history.filter(function(h) { return h !== text }))
  }

  // Keys in our prompt. Returns true when handled (not typed locally).
  function promptKey(event) {
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && input && input.selectedText !== "") {
      root.copy(input.selectedText)
      return true
    }
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && screenText.selectedText !== "") {
      root.copy(screenText.selectedText)
      screenText.deselect()
      return true
    }
    var plain = !(event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier))
    var empty = root.inputText === ""
    if (root.rawKeys) {
      var cmd = root.keyFor(event)
      if (cmd) root.send(cmd)
      return !!cmd
    }
    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && plain) {
      // Never into a dialog: wait for the prompt to come back.
      if (root.promptReady) root.submit()
      else if (empty) root.send({ keys: ["Enter"] })
      return true
    }
    if (event.key === Qt.Key_Backtab) { root.send({ keys: ["BTab"] }); return true }
    // An image on the clipboard goes to Claude as an attachment (live.py);
    // text still pastes here as usual.
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { root.send({ clip: true }); return false }
    // Backspace at (or inside) an @path chip takes the whole chip off, and
    // the space after it.
    if (event.key === Qt.Key_Backspace && plain && input.selectedText === "") {
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
    // Backspace on an empty prompt takes the last image back off.
    if (empty && event.key === Qt.Key_Backspace && root.attachments.length) { root.send({ keys: ["BSpace"] }); return true }
    if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C && input.selectedText === "") {
      if (empty) root.send({ keys: ["C-c"] })
      else input.text = ""
      return true
    }
    // Tab (or →) takes the suggestion, as in Claude's own prompt.
    if (root.suggesting && plain && (event.key === Qt.Key_Tab || event.key === Qt.Key_Right)) {
      input.text = root.suggestion
      input.cursorPosition = input.text.length
      return true
    }
    if (plain && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
      var caret = input.cursorRectangle
      if (event.key === Qt.Key_Up && caret.y < caret.height / 2) { root.recall(root.historyAt + 1); return true }
      if (event.key === Qt.Key_Down && caret.y + caret.height * 1.5 > input.contentHeight) { root.recall(root.historyAt - 1); return true }
      return false
    }
    // Scrolling, completion: the terminal's, while ours is empty.
    if (empty && [Qt.Key_PageUp, Qt.Key_PageDown, Qt.Key_Tab].indexOf(event.key) >= 0) {
      root.send(root.keyFor(event))
      return true
    }
    return false
  }

  // Qt key → tmux key name. Printable text goes literally.
  function keyFor(event) {
    var named = {}
    named[Qt.Key_Return] = "Enter"; named[Qt.Key_Enter] = "Enter"
    named[Qt.Key_Backspace] = "BSpace"; named[Qt.Key_Delete] = "DC"
    named[Qt.Key_Escape] = "Escape"; named[Qt.Key_Tab] = "Tab"; named[Qt.Key_Backtab] = "BTab"
    named[Qt.Key_Up] = "Up"; named[Qt.Key_Down] = "Down"; named[Qt.Key_Left] = "Left"; named[Qt.Key_Right] = "Right"
    named[Qt.Key_Home] = "Home"; named[Qt.Key_End] = "End"
    named[Qt.Key_PageUp] = "PPage"; named[Qt.Key_PageDown] = "NPage"
    var ctrl = event.modifiers & Qt.ControlModifier
    var alt = event.modifiers & Qt.AltModifier
    var name = named[event.key]
    if (name) {
      if (name === "Enter" && (event.modifiers & Qt.ShiftModifier)) return { keys: ["M-Enter"] }   // newline in the prompt
      return { keys: [(ctrl ? "C-" : "") + (alt ? "M-" : "") + name] }
    }
    if (ctrl && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
      return { keys: [(alt ? "M-" : "") + "C-" + String.fromCharCode(97 + event.key - Qt.Key_A)] }
    if (event.text && event.text.length && event.text.charCodeAt(0) >= 32)
      return alt ? { keys: ["M-" + event.text] } : { text: event.text }
    return null
  }

  Process {
    id: view
    stdinEnabled: true
    running: root.jobId !== "" && root.started
    command: ["python3", "-I", root.livePath, "view", root.jobId, String(root.cols), String(root.rows),
              String(root.fg), "#000000", String(root.mutedFg)]
    stdout: SplitParser {
      onRead: function(line) {
        var frame
        try { frame = JSON.parse(line) } catch (e) { return }
        root.scrolled = frame.scrolled === true
        root.unread = frame.unread || 0
        if (typeof frame.html === "string") {
          if (root.selecting) root.heldPage = frame.html
          else root.page = frame.html
        }
        root.framed = true
        root.alive = frame.alive !== false
        if (frame.model) root.screenModel = frame.model
        if (frame.mode) root.screenMode = frame.mode
        if (frame.effort) root.screenEffort = frame.effort
        root.promptReady = frame.prompt === true
        root.attachments = frame.attachments || []
        root.suggestion = frame.suggestion || ""
        root.draft = frame.draft || ""
      }
    }
    onExited: root.alive = false
  }

  // Start once the width is known, so the first frame comes out the right size.
  Component.onCompleted: {
    loadHistory()
    if (keyWindow) keyWindow.handler = root.promptKey
    Qt.callLater(function() { root.started = true })
  }
  Component.onDestruction: if (keyWindow && keyWindow.handler === root.promptKey) keyWindow.handler = null

  // Selecting text copies it, and so does Ctrl+C while there's a selection.
  property double copiedAt: 0
  // Mid-drag, frames wait in heldPage: replacing the text drops the selection.
  property bool selecting: false
  property var heldPage: null
  // The card scrolls in a Flickable, which takes any drag for itself; it
  // stays still while this is true so a drag here selects instead.
  readonly property bool holdsPointer: screenHover.hovered || selecting

  function endSelecting() {
    selecting = false
    if (heldPage !== null) { page = heldPage; heldPage = null }
  }

  function copy(text) {
    // Rich text selects with paragraph separators, and terminal rows end in padding.
    text = text.replace(/[\u2028\u2029]/g, "\n").replace(/\u00a0/g, " ").replace(/[ \t]+$/gm, "")
    if (!text.trim()) return
    Quickshell.execDetached(["wl-copy", "--", text])
    root.copiedAt = Date.now()
    copiedTimer.restart()
  }

  Timer {
    id: copiedTimer
    interval: 1200
    onTriggered: root.copiedAt = 0
  }

  property double pathCopiedAt: 0
  Timer {
    id: pathCopiedTimer
    interval: 1200
    onTriggered: root.pathCopiedAt = 0
  }

  // Click into the view (or a chip): take the keyboard back, and close the menu.
  function focusInput() {
    root.picker = ""
    root.grabbed()
    if (keyWindow) keyWindow.prime()
  }

  // The field lays its text out exactly like the drawing, so its caret
  // position can be used as-is.
  // RestoreNone: going away, it mustn't put back a size the chat or search
  // view has since set.
  Binding { target: root.keyWindow; property: "fieldWidth"; value: inputView.width; when: !!root.keyWindow; restoreMode: Binding.RestoreNone }
  Binding { target: root.keyWindow; property: "fontSize"; value: root.fontSize; when: !!root.keyWindow; restoreMode: Binding.RestoreNone }
  Binding { target: root.keyWindow; property: "fieldWrap"; value: true; when: !!root.keyWindow; restoreMode: Binding.RestoreNone }
  onColsChanged: if (started) send({ size: [cols, rows] })
  // Another session picked: restart the viewer on it.
  onJobIdChanged: if (started) {
    started = false; page = ""; framed = false; screenModel = ""; screenMode = ""; screenEffort = ""; scrolled = false; unread = 0
    promptReady = false; attachments = []; suggestion = ""; draft = ""; historyAt = -1
    Qt.callLater(function() { root.started = true })
  }

  // Drawn in the island's colors when it passes its palette (the detail
  // view); fg / mutedFg / accent otherwise.
  property QtObject pal: null
  readonly property color ink: pal ? pal.fg : fg
  readonly property color quietInk: pal ? pal.muted : mutedFg
  readonly property color hot: pal ? pal.crab : accent
  readonly property bool focused: !!root.input && root.input.activeFocus
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // A pill of session info: mode and folder up top, model and effort under
  // the composer.
  component InfoChip: Rectangle {
    id: chip
    property string label: ""
    property bool loud: false
    property real maxWidth: 100000
    // A picker chip: opens its choices under the composer.
    property bool clickable: false
    property bool open: false
    // Opus Plan: on its Shimmer, drifting while pointed at or open.
    property bool special: false
    // Effort's level color, for the text; transparent for none.
    property color tone: "transparent"
    signal clicked()
    width: Math.min(chipText.implicitWidth + Style.space(18), maxWidth)
    height: Style.space(24)
    radius: root.pal.pill(height)
    color: loud ? root.tint(root.hot, 0.18)
      : open ? root.tint(root.ink, 0.16)
      : clickable && chipMouse.containsMouse ? root.tint(root.ink, 0.12) : root.tint(root.ink, 0.07)
    border.width: 1
    border.color: loud ? root.tint(root.hot, 0.4) : root.tint(root.ink, 0.06)

    Shimmer {
      visible: chip.special
      anchors.fill: parent
      radius: parent.radius
      from: root.hot
      to: root.pal ? root.pal.limit : root.hot
      running: chip.open || chipMouse.containsMouse
    }

    Text {
      id: chipText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, chip.maxWidth - Style.space(18))
      text: chip.label
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      color: chip.loud ? root.hot : chip.tone.a > 0 ? chip.tone : chip.open || chip.special ? root.ink : root.quietInk
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      enabled: chip.clickable
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  // Title (or the status) and the session's mode and folder as chips, in
  // place of the terminal's own banner and status lines.
  Item {
    width: parent.width
    height: Math.max(infoRow.implicitHeight, statusRow.implicitHeight)

    Text {
      visible: root.showTitle
      anchors.left: parent.left
      anchors.right: infoRow.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: (root.alive ? "● " : "○ ") + root.title + (root.alive ? "" : " · detached")
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: root.alive ? root.hot : root.quietInk
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Row {
      id: infoRow
      x: root.showTitle ? parent.width - width : 0
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      InfoChip {
        id: modeChip
        visible: root.modeLabel !== ""
        label: root.modeLabel
        // Plan and bypass change what Claude may do: those stand out.
        loud: /plan|bypass/i.test(root.modeLabel)
        // Click cycles to the next mode, like ⇧Tab.
        clickable: true
        onClicked: { root.send({ keys: ["BTab"] }); root.focusInput() }
      }

      // The folder takes what's left beside the status, eliding its middle.
      // Click to copy the full path; the label says so for a moment.
      InfoChip {
        visible: root.cwdLabel !== ""
        label: root.pathCopiedAt > 0 ? "Copied" : root.cwdLabel
        clickable: true
        onClicked: {
          Quickshell.execDetached(["wl-copy", "--", root.cwd])
          root.pathCopiedAt = Date.now()
          pathCopiedTimer.restart()
          root.focusInput()
        }
        maxWidth: (root.showTitle ? root.width / 2 : root.width - statusRow.width - Style.space(12))
          - (modeChip.visible ? modeChip.width + infoRow.spacing : 0)
      }
    }

    // live · 2m 14s, with a dot that breathes while it's attached.
    Row {
      id: statusRow
      visible: !root.showTitle
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(7)

      Rectangle {
        id: liveDot
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(7)
        height: width
        radius: width / 2
        color: root.jobId === "" ? root.hot : root.alive ? (root.pal ? root.pal.done : root.hot) : root.quietInk
        Throb { target: liveDot; running: root.alive && root.visible; period: 1800; steps: 12 }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.jobId === "" ? "starting" : root.alive ? root.status : "detached"
        textFormat: Text.PlainText
        color: root.quietInk
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  // The terminal: a dark well, the conversation in it.
  Rectangle {
    id: screenBox
    width: parent.width
    height: screenArea.height + root.pad * 2
    radius: root.screenRadius
    color: root.screenColor
    border.width: 1
    border.color: root.tint(root.ink, 0.06)
    clip: true

    HoverHandler { id: screenHover }

    // Under the text, so a press on the text reaches it and can select.
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      onClicked: root.focusInput()
      onWheel: function(wheel) { root.scrollBy(wheel) }
    }

    // The conversation: grows with it, up to `rows` lines.
    Item {
      id: screenArea
      x: root.pad
      y: root.pad
      width: parent.width - root.pad * 2
      // Where the height is headed: the text is placed against this, not the
      // animated height, or every new line would bounce it up and back down.
      // Always the full `rows`: a short conversation, a new session or one
      // scrolled back never moves the card. Less what the composer has grown
      // by, exactly: rounding to whole lines made the card shrink a bit whenever the
      // composer grew by a fraction of one.
      readonly property real targetHeight: Math.max(root.lineHeight * 4, root.lineHeight * root.rows - root.composerGrowth)
      height: targetHeight
      clip: true

      TextEdit {
        id: screenText
        z: 1
        width: parent.width
        y: Math.min(0, screenArea.targetHeight - implicitHeight)
        text: root.page
        textFormat: TextEdit.RichText
        readOnly: true
        selectByMouse: true
        persistentSelection: true
        activeFocusOnPress: false
        selectionColor: root.tint(root.hot, 0.45)
        selectedTextColor: root.ink
        color: root.ink
        font.family: "monospace"
        font.pixelSize: root.fontSize

        // Passive, so the drag still selects: on release a selection is
        // copied, a plain click goes back to typing.
        PointHandler {
          acceptedButtons: Qt.LeftButton
          onActiveChanged: {
            if (active) { root.selecting = true; return }
            if (screenText.selectedText) root.copy(screenText.selectedText)
            else root.focusInput()
            root.endSelecting()
          }
        }
      }

      // Older lines fade out under the top edge once it's full.
      Rectangle {
        visible: screenText.implicitHeight > screenArea.targetHeight
        z: 2
        width: parent.width
        height: root.lineHeight * 1.5
        gradient: Gradient {
          GradientStop { position: 0; color: root.screenColor }
          GradientStop { position: 1; color: root.tint(root.screenColor, 0) }
        }
      }

      Rectangle {
        visible: root.copiedAt > 0
        z: 3
        anchors.top: parent.top
        anchors.right: parent.right
        width: copiedText.implicitWidth + Style.space(16)
        height: Style.space(22)
        radius: pal.pill(height)
        color: root.tint(root.hot, 0.18)

        Text {
          id: copiedText
          anchors.centerIn: parent
          text: "Copied"
          textFormat: Text.PlainText
          color: root.hot
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // Floats over the conversation, so it never changes the height.
      Rectangle {
        visible: root.scrolled
        z: 4
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: jumpRow.implicitWidth + Style.space(24)
        height: Style.space(30)
        radius: pal.pill(height)
        color: root.pal ? root.pal.raised : root.screenColor
        border.width: 1
        border.color: jumpMouse.containsMouse ? root.tint(root.hot, 0.6) : root.tint(root.ink, 0.16)

        Row {
          id: jumpRow
          anchors.centerIn: parent
          spacing: Style.space(7)

          Icon {
            anchors.verticalCenter: parent.verticalCenter
            d: "M12 5v14M6 13l6 6 6-6"
            size: Style.space(13)
            stroke: 2.2
            color: root.hot
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.unread > 0 ? root.unread + (root.unread === 1 ? " new message" : " new messages") : "Jump to bottom"
            textFormat: Text.PlainText
            color: root.ink
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: jumpMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.send({ keys: ["C-End"] }); root.focusInput() }
        }
      }

      Column {
        visible: root.page === ""
        anchors.centerIn: parent
        spacing: Style.space(6)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.jobId === "" ? "Starting Claude…" : root.framed ? "New session" : "Attaching…"
          textFormat: Text.PlainText
          color: root.ink
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          visible: root.framed && root.jobId !== ""
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Type below to start"
          textFormat: Text.PlainText
          color: root.quietInk
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  // The linked chip under the pointer, and the full path to show for it.
  property string tipLink: ""
  property Item tipSeg: null

  // How much taller than one line the composer is (a long message, images).
  readonly property real composerGrowth: Math.max(0, composer.height - Math.max(metrics.lineSpacing, Style.space(28)) - Style.space(10) * 2)
  // Past this many lines, the message scrolls inside the composer.
  property int inputLines: 6
  property real inputScroll: 0

  function keepCaretShown() {
    if (!input) return
    var c = input.cursorRectangle
    var s = Math.min(root.inputScroll, c.y)
    s = Math.max(s, c.y + c.height - inputView.height)
    root.inputScroll = Math.max(0, Math.min(s, shown.implicitHeight - inputView.height))
  }

  // The composer: our prompt in its own rounded box under the terminal,
  // with a send button. Amber while Claude's asking something and keys go
  // straight to the terminal.
  Rectangle {
    id: composer
    width: parent.width
    height: promptArea.implicitHeight + Style.space(10) * 2
    radius: pal.pill(height)
    color: root.pal ? root.pal.raised : root.tint(root.ink, 0.06)
    border.width: 1
    border.color: !root.alive ? root.tint(root.ink, 0.08)
      : root.rawKeys && root.pal ? root.tint(root.pal.needsYou, 0.55)
      : root.focused ? root.tint(root.hot, 0.6)
      : root.tint(root.ink, 0.12)
    Behavior on border.color { ColorAnimation { duration: 140 } }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      onClicked: root.focusInput()
    }

    // The full path of the link chip under the pointer.
    Rectangle {
      visible: root.tipLink !== "" && root.tipSeg !== null
      readonly property point at: root.tipSeg ? root.tipSeg.mapToItem(composer, 0, 0) : Qt.point(0, 0)
      x: Math.max(0, Math.min(at.x, composer.width - width))
      y: at.y - height - Style.space(6)
      width: Math.min(tipText.implicitWidth + Style.space(14), composer.width)
      height: tipText.implicitHeight + Style.space(8)
      radius: pal.rad(Style.space(8))
      z: 20
      color: root.pal ? root.pal.raised : "black"
      border.width: 1
      border.color: root.pal ? root.pal.line : "transparent"

      Text {
        id: tipText
        anchors.centerIn: parent
        width: parent.width - Style.space(14)
        text: root.tipLink
        textFormat: Text.PlainText
        elide: Text.ElideMiddle
        color: root.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Column {
      id: promptArea
      x: Style.space(16)
      y: Style.space(10)
      width: parent.width - x - sendButton.width - attachButton.width - Style.space(6) - Style.space(10) - Style.space(10)
      spacing: Style.space(6)

      Flow {
        visible: root.attachments.length > 0
        width: parent.width
        spacing: Style.space(5)

        Repeater {
          model: root.attachments

          Rectangle {
            required property string modelData
            implicitWidth: attachText.implicitWidth + Style.space(16)
            implicitHeight: Style.space(24)
            radius: pal.pill(height)
            color: root.tint(root.hot, 0.16)
            border.width: 1
            border.color: root.tint(root.hot, 0.4)

            Text {
              id: attachText
              anchors.centerIn: parent
              text: "  " + parent.modelData.replace(/^\[|\]$/g, "")
              textFormat: Text.PlainText
              color: root.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Math.max(inputView.height, metrics.lineSpacing, Style.space(28))

        Text {
          id: caret
          anchors.verticalCenter: parent.verticalCenter
          text: "❯"
          textFormat: Text.PlainText
          color: root.rawKeys ? root.quietInk : root.hot
          font.family: "monospace"
          font.pixelSize: root.fontSize
          font.bold: true
        }

        Item {
          id: inputView
          anchors.left: caret.right
          anchors.leftMargin: metrics.averageCharacterWidth
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          readonly property real lineStep: shown.lineCount > 0 ? shown.implicitHeight / shown.lineCount : metrics.lineSpacing
          height: Math.min(shown.implicitHeight, lineStep * root.inputLines)
          clip: true
          onHeightChanged: root.keepCaretShown()

          Connections {
            target: root.input
            function onCursorRectangleChanged() { root.keepCaretShown() }
          }

          // The field's text, and its selection: the field (KeyWindow) is
          // laid out the same, so positions carry over both ways.
          TextEdit {
            id: shown
            y: -root.inputScroll
            width: parent.width
            text: root.inputText
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            readOnly: true
            activeFocusOnPress: false
            selectByMouse: false
            cursorVisible: false
            color: root.ink
            selectionColor: root.tint(root.hot, 0.4)
            selectedTextColor: root.ink
            font.family: "monospace"
            font.pixelSize: root.fontSize
            onTextChanged: mirrorSelection()
            onImplicitHeightChanged: root.keepCaretShown()
            function mirrorSelection() {
              if (root.input) shown.select(root.input.selectionStart, root.input.selectionEnd)
            }
          }

          Connections {
            target: root.input
            function onSelectionStartChanged() { shown.mirrorSelection() }
            function onSelectionEndChanged() { shown.mirrorSelection() }
          }

          // Click puts the caret there, a drag selects, a double-click takes
          // the word; Ctrl+C copies it, typing replaces it.
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.IBeamCursor
            property int anchorAt: 0
            function at(mouse) { return shown.positionAt(mouse.x - Style.space(4), mouse.y - Style.space(4) + root.inputScroll) }
            onWheel: function(wheel) {
              var dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y / 120 * inputView.lineStep * 3
              root.inputScroll = Math.max(0, Math.min(root.inputScroll - dy, shown.implicitHeight - inputView.height))
            }
            onPressed: function(mouse) {
              root.focusInput()
              if (!root.input) return
              anchorAt = at(mouse)
              root.input.cursorPosition = anchorAt
            }
            onPositionChanged: function(mouse) {
              if (pressed && root.input) root.input.select(anchorAt, at(mouse))
            }
            onDoubleClicked: function(mouse) {
              if (!root.input) return
              root.input.cursorPosition = at(mouse)
              root.input.selectWord()
            }
          }

          // Linked files and folders as chips, inline: a wash behind the @path
          // (the text stays put, so the field's positions still carry over);
          // hover for the full path. Clicks go on to the area below.
          Repeater {
            model: root.links

            Item {
              id: link
              required property var modelData
              readonly property real charW: metrics.averageCharacterWidth
              readonly property var first: { shown.text; shown.width; shown.contentHeight; return shown.positionToRectangle(modelData.start) }
              readonly property var last: { shown.text; shown.width; shown.contentHeight; return shown.positionToRectangle(modelData.end - 1) }
              readonly property bool wraps: last.y > first.y + 1

              component Segment: Rectangle {
                id: seg
                height: link.first.height - 2
                radius: height / 2.6
                color: root.tint(root.hot, seg.hovered ? 0.24 : 0.12)
                border.width: 1
                border.color: root.tint(root.hot, seg.hovered ? 0.55 : 0.3)
                readonly property bool hovered: segMouse.containsMouse

                MouseArea {
                  id: segMouse
                  anchors.fill: parent
                  acceptedButtons: Qt.NoButton
                  hoverEnabled: true
                  onContainsMouseChanged: {
                    if (containsMouse) { root.tipLink = link.modelData.path; root.tipSeg = seg }
                    else if (root.tipSeg === seg) { root.tipLink = ""; root.tipSeg = null }
                  }
                }
              }

              Segment {
                x: link.first.x - Style.space(2)
                y: link.first.y + 1 - root.inputScroll
                width: (link.wraps ? shown.width : link.last.x + link.charW) - link.first.x + Style.space(4)
              }

              Segment {
                visible: link.wraps
                x: -Style.space(2)
                y: link.last.y + 1 - root.inputScroll
                width: link.last.x + link.charW + Style.space(4)
              }
            }
          }

          // Scrollbar, once the message overflows the box.
          Rectangle {
            id: inputBar
            readonly property real overflow: shown.implicitHeight - inputView.height
            visible: overflow > 1
            z: 3
            anchors.right: parent.right
            width: Math.max(3, Style.spaceReal(3))
            radius: width / 2
            height: Math.max(Style.space(16), inputView.height * inputView.height / shown.implicitHeight)
            y: overflow > 0 ? (inputView.height - height) * root.inputScroll / overflow : 0
            color: root.tint(root.ink, 0.35)
          }

          Rectangle {
            id: cursorBlock
            visible: root.alive && root.focused && !root.rawKeys
            x: root.input ? root.input.cursorRectangle.x : 0
            y: root.input ? root.input.cursorRectangle.y - root.inputScroll : 0
            width: Math.max(2, Style.spaceReal(2))
            height: root.input ? root.input.cursorRectangle.height : metrics.lineSpacing
            radius: width / 2
            color: root.hot
            SequentialAnimation on opacity {
              running: cursorBlock.visible
              loops: Animation.Infinite
              NumberAnimation { to: 1; duration: 0 }
              PauseAnimation { duration: 530 }
              NumberAnimation { to: 0; duration: 0 }
              PauseAnimation { duration: 530 }
            }
          }

          Text {
            id: placeholder
            visible: root.inputText === ""
            width: root.suggesting ? Math.min(implicitWidth, parent.width - x - tabHint.width - Style.space(10)) : parent.width - x
            x: cursorBlock.visible ? cursorBlock.width + Style.space(4) : 0
            text: root.jobId === "" ? "Starting…"
              : !root.alive ? "Session ended"
              : root.rawKeys ? "Claude is asking: keys go to the terminal above"
              : root.suggesting ? root.suggestion
              : root.focused ? (root.attachments.length ? "Add a message, or Enter to send the image" : "Message Claude…")
              : "Click to reply"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.rawKeys && root.pal ? root.pal.needsYouText : root.quietInk
            // A suggestion in the typed text's font: Tab types exactly this.
            font.family: root.suggesting ? "monospace" : Style.font.family
            font.pixelSize: root.fontSize
          }

          Text {
            id: tabHint
            visible: root.suggesting
            x: placeholder.x + placeholder.width + Style.space(10)
            anchors.baseline: placeholder.baseline
            text: "Tab"
            textFormat: Text.PlainText
            color: root.pal ? root.pal.dim : root.mutedFg
            font.family: Style.font.family
            font.pixelSize: Math.round(root.fontSize * 0.85)
          }
        }
      }
    }

    // Link files or a folder: the chooser, from the choices under the composer.
    Rectangle {
      id: attachButton
      anchors.right: sendButton.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: sendButton.verticalCenter
      width: Style.space(28)
      height: width
      radius: width / 2
      color: root.picker === "attach" || root.picking ? root.tint(root.ink, 0.14)
        : attachMouse.containsMouse ? root.tint(root.ink, 0.08) : "transparent"
      Behavior on color { ColorAnimation { duration: 120 } }

      Icon {
        anchors.centerIn: parent
        d: Icons.clip
        size: Style.space(15)
        stroke: 2
        color: attachMouse.containsMouse || root.picker === "attach" ? root.ink : root.quietInk
      }

      MouseArea {
        id: attachMouse
        anchors.fill: parent
        enabled: root.alive && !root.picking
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.togglePicker("attach", attachButton)
      }
    }

    // Send: filled once there's something to send.
    Rectangle {
      id: sendButton
      readonly property bool ready: root.alive && root.promptReady && (root.inputText.trim() !== "" || root.attachments.length > 0)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: (Style.space(10) * 2 + Style.space(28) - height) / 2
      width: Style.space(32)
      height: width
      radius: width / 2
      color: ready ? (root.pal ? root.pal.primary : root.ink) : root.tint(root.ink, 0.08)
      scale: sendMouse.pressed && ready ? 0.92 : 1
      Behavior on color { ColorAnimation { duration: 120 } }
      Behavior on scale { NumberAnimation { duration: 90 } }

      Icon {
        anchors.centerIn: parent
        d: "M12 19V5M6 11l6-6 6 6"
        size: Style.space(16)
        stroke: 2.4
        color: sendButton.ready ? (root.pal ? root.pal.primaryInk : root.screenColor) : root.quietInk
      }

      MouseArea {
        id: sendMouse
        anchors.fill: parent
        cursorShape: sendButton.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { if (sendButton.ready) root.submit(); root.focusInput() }
      }
    }
  }

  // Key hints on the left (the key in a small outlined box, then what it
  // does; Esc and ⇧Tab can be clicked), model and effort on the right.
  Item {
    id: footer
    width: parent.width
    height: Math.max(hintsRow.implicitHeight, modelRow.implicitHeight)

    Row {
      id: modelRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      // Click for the choices: /model and /effort, sent to the session.
      InfoChip {
        id: modelChip
        visible: root.modelLabel !== "" || root.canCommand
        label: root.modelLabel || "Model"
        clickable: root.canCommand
        open: root.picker === "model"
        special: root.opusPlan
        onClicked: root.togglePicker("model", modelChip)
      }
      InfoChip {
        id: effortChip
        visible: root.effortLabel !== "" || root.canCommand
        label: root.effortLabel || "Effort"
        tone: root.pal && root.currentEffort ? root.pal.effort(root.currentEffort) : "transparent"
        clickable: root.canCommand
        open: root.picker === "effort"
        onClicked: root.togglePicker("effort", effortChip)
      }
    }

    Row {
      id: hintsRow
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(14)

      component Hint: Item {
        id: hint
        property string key: ""
        property string label: ""
        property bool clickable: false
        signal clicked()
        implicitWidth: hintRow.implicitWidth
        implicitHeight: hintRow.implicitHeight
        opacity: hintMouse.containsMouse ? 1 : 0.85

        Row {
          id: hintRow
          spacing: Style.space(6)

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.max(height, keyText.implicitWidth + Style.space(10))
            implicitHeight: Style.space(20)
            radius: pal.rad(Style.space(6))
            color: hint.clickable && hintMouse.containsMouse ? root.tint(root.ink, 0.10) : "transparent"
            border.width: 1
            border.color: root.tint(root.ink, 0.2)

            Text {
              id: keyText
              anchors.centerIn: parent
              text: hint.key
              textFormat: Text.PlainText
              color: root.ink
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.label
            textFormat: Text.PlainText
            color: root.quietInk
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: hintMouse
          anchors.fill: parent
          enabled: hint.clickable
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: hint.clicked()
        }
      }

      Hint { key: "Ctrl C"; label: "interrupt"; clickable: true; onClicked: { root.send({ keys: ["Escape"] }); root.focusInput() } }
      Hint { key: "⇧Tab"; label: "mode"; clickable: true; onClicked: { root.send({ keys: ["BTab"] }); root.focusInput() } }
      Hint { key: "⇧ Enter"; label: "new line" }
      // Room for it beside the model and effort only on a wide card.
      Hint { visible: root.width > Style.space(700); key: "Ctrl V"; label: "image" }
      Hint { visible: root.showWindowChips; key: "↗"; label: "Open in terminal"; clickable: true; onClicked: root.openTerminal() }
      Hint { visible: root.showWindowChips; key: "—"; label: "Collapse"; clickable: true; onClicked: root.collapse() }
    }

    // The open chip's (or the paperclip's) choices: a menu rising from it,
    // over the composer and the terminal, so nothing under it moves.
    PickMenu {
      pal: root.pal
      id: pickerMenu
      // The anchor's top-right corner, here.
      readonly property point at: root.picker !== "" && root.pickerAnchor
        ? root.pickerAnchor.mapToItem(footer, root.pickerAnchor.width, 0) : Qt.point(0, 0)
      visible: root.picker !== ""
      z: 10
      x: Math.max(0, at.x - width)
      y: at.y - height - Style.space(6)
      minWidth: root.pickerAnchor ? root.pickerAnchor.width : 0
      title: root.picker === "model" ? "Model" : root.picker === "effort" ? "Effort" : "Link"
      options: root.pickerOptions
      current: root.pickerCurrent
      ink: root.ink
      quietInk: root.quietInk
      hot: root.hot
      glow: root.pal ? root.pal.limit : root.hot
      fill: root.pal ? root.pal.raised : root.screenColor
      onPicked: function(id) { root.pick(id) }
    }
  }
}
