import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// The new chat view (the nav's chat icon, Super+Alt+C): what's typed lands in
// the key window's field (the card can't take keys) and is drawn here by
// MirrorInput. Chat or Code, whichever was used last; Enter starts that
// session with the message as its first prompt. `compact` is the view itself:
// no frame of its own. Without it, it's the chatbox typing opens over the
// other views of a summoned island.
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property var field: null
  property string mode: "chat"
  property string chatDir: ""
  property string codeDir: ""
  property int fontSize: Style.font.subtitle
  property bool compact: false
  property bool focused: true
  // The model new sessions start on: a `claude --model` alias, "" for Claude's
  // own default. Its chip in the composer opens the choices, as does effort's.
  property string model: ""
  readonly property var models: [
    { id: "", label: "Default" },
    { id: "opus", label: "Opus" },
    { id: "sonnet", label: "Sonnet" },
    { id: "haiku", label: "Haiku" },
    { id: "fable", label: "Fable" },
    { id: "opusplan", label: "Opus Plan", special: true }
  ]
  readonly property string modelLabel: {
    for (var i = 0; i < models.length; i++) if (models[i].id === model) return models[i].label
    return model
  }
  // And the effort (`claude --effort`), "" for the default.
  property string effort: ""
  // xhigh → Extra high, as the live view says it.
  function effortName(e) {
    e = String(e || "")
    return e === "xhigh" ? "Extra high" : e ? e.charAt(0).toUpperCase() + e.slice(1) : "Default"
  }
  readonly property var efforts: ["", "low", "medium", "high", "xhigh", "max"].map(function(e) { return { id: e, label: effortName(e), tone: pal.effort(e) } })
  // Code's permission mode (`claude --permission-mode`), picked beside the folder.
  property string permission: "auto"
  readonly property var permissions: [
    { id: "auto", label: "Auto mode" },
    { id: "plan", label: "Plan mode" },
    { id: "acceptEdits", label: "Accept edits" },
    { id: "default", label: "Ask before edits" }
  ]
  readonly property string permissionLabel: {
    for (var i = 0; i < permissions.length; i++) if (permissions[i].id === permission) return permissions[i].label
    return permission
  }
  // The folder Code starts in: "" for the Code folder. Its label opens the
  // choices: the Code folder, the one Claude worked in last, or any.
  property string dir: ""
  property string recentDir: ""
  // Pasted images waiting to go with the message (paths); Ctrl+V adds them.
  property var images: []
  readonly property string startDir: mode === "code" ? (dir || codeDir) : chatDir
  // Laid out like this, the field's caret lines up with the drawing.
  readonly property real inputWidth: shown.width

  // The open menu: "model", "effort", "mode", "folder", "attach" or "". It drops
  // from its chip into `menuLayer` (the card's float layer, so it can hang
  // past the island's bottom instead of stretching it); menuItem is it there.
  property string picker: ""
  property Item pickerAnchor: null
  property Item menuLayer: null
  readonly property Item menuItem: menu
  onVisibleChanged: if (!visible) picker = ""
  onModeChanged: if (picker === "folder" || picker === "mode") picker = ""

  signal picked(string mode)
  signal modelPicked(string model)
  signal effortPicked(string effort)
  signal dirPicked(string dir)
  signal permissionPicked(string permission)
  signal send()
  signal imageRemoved(int index)
  // Clicked into the composer: the key window takes the keyboard back.
  signal focusRequested()

  readonly property string text: field ? field.text : ""
  readonly property string home: Quickshell.env("HOME") || ""

  function togglePicker(which, anchor) {
    var opening = root.picker !== which
    root.picker = ""
    if (opening) { root.pickerAnchor = anchor; root.picker = which }
    root.focusRequested()
  }

  function pick(id) {
    var which = root.picker
    root.picker = ""
    if (which === "model") root.modelPicked(id)
    else if (which === "effort") root.effortPicked(id)
    else if (which === "mode") root.permissionPicked(id)
    else if (which === "folder") { if (id === "browse") { root.browse("dir"); return } root.dirPicked(id) }
    else if (which === "attach") { root.browse(id); return }
    root.focusRequested()
  }

  // Straight to the next permission mode, as ⇧Tab does in a live session.
  // The mode chip's click and ⇧Tab here both call it.
  function cyclePermission() {
    root.picker = ""
    for (var i = 0; i < root.permissions.length; i++)
      if (root.permissions[i].id === root.permission) break
    root.permissionPicked(root.permissions[(i + 1) % root.permissions.length].id)
  }

  readonly property var pickerOptions: {
    if (picker === "model") return models
    if (picker === "effort") return efforts
    if (picker === "mode") return permissions
    if (picker === "attach") return [{ id: "files", label: "Files…" }, { id: "folder", label: "Folder…" }]
    if (picker !== "folder") return []
    var out = [{ id: "", label: Format.folder(codeDir, home), hint: "Code folder" }]
    if (recentDir && recentDir !== codeDir) out.push({ id: recentDir, label: Format.folder(recentDir, home), hint: "last used" })
    if (dir && dir !== recentDir) out.push({ id: dir, label: Format.folder(dir, home) })
    out.push({ id: "browse", label: "Open folder…" })
    return out
  }

  // The desktop's file chooser: a folder for Code to start in ("dir"), or
  // files or a folder to point Claude at, typed in as @path like LiveTerm's.
  readonly property bool picking: browser.running
  property string browsing: ""
  Process {
    id: browser
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var paths = text.split("\n").filter(function(p) { return p[0] === "/" })
        if (root.browsing === "dir") { if (paths.length) root.dirPicked(paths[0]) }
        else root.mention(paths)
        root.focusRequested()
      }
    }
  }

  function browse(kind) {
    if (browser.running) return
    root.browsing = kind
    var title = kind === "dir" ? "Open Claude in a folder" : kind === "folder" ? "Link a folder" : "Link files"
    browser.command = ["sh", "-c", 'command -v zenity >/dev/null || { notify-send -a Clawdius "File pickers need zenity" "Install it: sudo pacman -S zenity"; exit 1; }; exec zenity "$@"', "clawdius-zenity", "--file-selection", "--filename=" + (root.startDir || root.home) + "/", "--title=" + title]
      .concat(kind === "files" ? ["--multiple", "--separator=\n"] : ["--directory"])
    browser.running = true
  }

  // Inside the folder it starts in relative, else absolute; quoted if it has spaces.
  function mention(paths) {
    var base = root.startDir
    var refs = []
    for (var i = 0; i < paths.length; i++) {
      var path = paths[i]
      if (base && path === base) path = "."
      else if (base && path.indexOf(base + "/") === 0) path = path.slice(base.length + 1)
      refs.push(/\s/.test(path) ? '@"' + path + '"' : "@" + path)
    }
    if (!refs.length || !field) return
    var at = field.cursorPosition
    var before = field.text.slice(0, at)
    var add = (before && !/\s$/.test(before) ? " " : "") + refs.join(" ") + " "
    field.text = before + add + field.text.slice(at)
    field.cursorPosition = at + add.length
  }

  readonly property real inset: compact ? Style.space(4) : Style.space(14)
  height: column.implicitHeight + inset * 2
  radius: pal.rad(Style.space(20))
  color: compact ? "transparent" : pal.card
  border.width: compact ? 0 : 1
  border.color: pal.alpha(pal.crab, 0.35)

  Column {
    id: column
    x: root.inset
    y: root.inset
    width: parent.width - root.inset * 2
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: toggle.height

      // Chat | Code, Tab switches.
      Rectangle {
        id: toggle
        width: toggleRow.implicitWidth + Style.space(4) * 2
        height: Style.space(32)
        radius: pal.pill(height)
        color: root.pal.alpha(root.pal.fg, 0.06)

        Row {
          id: toggleRow
          x: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Segment { which: "chat"; icon: Icons.chat; label: "Chat" }
          Segment { which: "code"; icon: Icons.code; label: "Code" }
        }
      }

      // In Code, the folder is a picker too.
      Item {
        id: dirLabel
        anchors.left: toggle.right
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        // Never under the hint on the right: a long folder elides its middle.
        readonly property real room: parent.width - toggle.width - Style.space(10) - hint.width - Style.space(12) - modeLabel.width
        width: Math.min(dirRow.implicitWidth, room)
        height: Style.space(26)

        Row {
          id: dirRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, dirLabel.room - (root.mode === "code" ? Style.space(15) : 0))
            elide: Text.ElideMiddle
            text: Format.folder(root.startDir, root.home) + (root.mode === "code" ? "" : " · talk only")
            textFormat: Text.PlainText
            color: root.mode === "code" && (root.picker === "folder" || dirMouse.containsMouse) ? root.pal.strong : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Icon {
            visible: root.mode === "code"
            anchors.verticalCenter: parent.verticalCenter
            d: "M6 9l6 6 6-6"
            size: Style.space(11)
            stroke: 2.4
            rotation: root.picker === "folder" ? 180 : 0
            color: root.pal.muted
            Behavior on rotation { NumberAnimation { duration: 140 } }
          }
        }

        MouseArea {
          id: dirMouse
          enabled: root.mode === "code"
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePicker("folder", dirLabel)
        }
      }

      // In Code, the permission mode is a picker too.
      Item {
        id: modeLabel
        visible: root.mode === "code"
        anchors.left: dirLabel.right
        anchors.verticalCenter: parent.verticalCenter
        width: visible ? modeRow.implicitWidth : 0
        height: Style.space(26)

        Row {
          id: modeRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: " · " + root.permissionLabel
            textFormat: Text.PlainText
            color: modeMouse.containsMouse ? root.pal.strong : root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          id: modeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.cyclePermission(); root.focusRequested() }
        }
      }

      Text {
        id: hint
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Tab switch · " + (root.mode === "code" ? "⇧Tab mode · " : "") + (root.compact && root.text === "" ? "Esc close" : "Esc clear")
        textFormat: Text.PlainText
        color: root.pal.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // Pasted images, as small thumbnails with a way to take each back off.
    Flow {
      visible: root.images.length > 0
      width: parent.width
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
              onClicked: root.imageRemoved(thumb.index)
            }
          }
        }
      }
    }

    // The composer, as LiveTerm draws its own.
    Rectangle {
      width: parent.width
      height: Math.max(Style.space(28), shown.implicitHeight) + Style.space(10) * 2
      radius: pal.pill(height)
      color: root.pal.raised
      border.width: 1
      border.color: root.pal.alpha(root.pal.crab, 0.55)

      MirrorInput {
        id: shown
        x: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - modelChip.width - effortChip.width - attachButton.width - sendButton.width - Style.space(8) * 3 - Style.space(6) * 2
        pal: root.pal
        field: root.field
        focused: root.focused
        fontSize: root.fontSize
        fontFamily: root.fontFamily
        placeholder: root.mode === "code" ? "What should Claude build?" : "Ask Claude anything…"
        onFocusRequested: root.focusRequested()
      }

      // Model and effort for the next session; each opens its menu.
      PickChip {
        id: modelChip
        anchors.right: effortChip.left
        anchors.rightMargin: Style.space(6)
        label: root.modelLabel
        quiet: root.model === ""
        special: root.model === "opusplan"
        open: root.picker === "model"
        onClicked: root.togglePicker("model", modelChip)
      }

      PickChip {
        id: effortChip
        anchors.right: attachButton.left
        anchors.rightMargin: Style.space(6)
        label: root.effort ? root.effortName(root.effort) + " effort" : "Effort"
        quiet: root.effort === ""
        tone: root.effort ? root.pal.effort(root.effort) : "transparent"
        open: root.picker === "effort"
        onClicked: root.togglePicker("effort", effortChip)
      }

      // Link files or a folder: the chooser, from its menu.
      Rectangle {
        id: attachButton
        anchors.right: sendButton.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(28)
        height: width
        radius: width / 2
        color: root.picker === "attach" || root.picking ? root.pal.alpha(root.pal.fg, 0.14)
          : attachMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.08) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        Icon {
          anchors.centerIn: parent
          d: Icons.clip
          size: Style.space(15)
          stroke: 2
          color: attachMouse.containsMouse || root.picker === "attach" ? root.pal.strong : root.pal.muted
        }

        MouseArea {
          id: attachMouse
          anchors.fill: parent
          enabled: !root.picking
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePicker("attach", attachButton)
        }
      }

      Rectangle {
        id: sendButton
        readonly property bool ready: root.text.trim() !== "" || root.images.length > 0
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(32)
        height: width
        radius: width / 2
        color: ready ? root.pal.primary : root.pal.alpha(root.pal.fg, 0.08)

        Icon {
          anchors.centerIn: parent
          d: "M12 19V5M6 11l6-6 6 6"
          size: Style.space(16)
          stroke: 2.4
          color: sendButton.ready ? root.pal.primaryInk : root.pal.muted
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: sendButton.ready ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (sendButton.ready) root.send()
        }
      }
    }
  }

  // The open chip's choices, dropping from it: the composer sits just under
  // the bar, so there's no room to rise as the live view's do. Lined up with
  // the chip's right edge, the folder's on its left.
  PickMenu {
    pal: root.pal
    id: menu
    parent: root.menuLayer || root
    readonly property point at: root.picker !== "" && root.pickerAnchor
      ? root.pickerAnchor.mapToItem(parent, root.picker === "folder" || root.picker === "mode" ? 0 : root.pickerAnchor.width, root.pickerAnchor.height)
      : Qt.point(0, 0)
    visible: root.picker !== "" && root.visible
    z: 20
    x: root.picker === "folder" || root.picker === "mode" ? at.x : Math.max(0, at.x - width)
    y: at.y + Style.space(6)
    minWidth: root.pickerAnchor ? root.pickerAnchor.width : 0
    title: root.picker === "model" ? "Model" : root.picker === "effort" ? "Effort" : root.picker === "mode" ? "Mode" : root.picker === "folder" ? "Start in" : "Link"
    options: root.pickerOptions
    current: root.picker === "model" ? root.model : root.picker === "effort" ? root.effort : root.picker === "mode" ? root.permission : root.picker === "folder" ? root.dir : "-"
    ink: root.pal.fg
    quietInk: root.pal.muted
    hot: root.pal.crab
    glow: root.pal.limit
    fill: root.pal.raised
    onPicked: function(id) { root.pick(id) }
  }

  component PickChip: Rectangle {
    id: chip
    property string label: ""
    property bool quiet: false
    property bool open: false
    // Opus Plan: on its Shimmer, drifting while pointed at or open.
    property bool special: false
    // Effort's level color, for the text; transparent for none.
    property color tone: "transparent"
    signal clicked()

    anchors.verticalCenter: parent.verticalCenter
    width: chipRow.implicitWidth + Style.space(12) * 2
    height: Style.space(26)
    radius: root.pal.pill(height)
    color: open ? root.pal.alpha(root.pal.fg, 0.14)
      : chipMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.10) : root.pal.alpha(root.pal.fg, 0.06)
    Behavior on color { ColorAnimation { duration: 120 } }

    Shimmer {
      visible: chip.special
      anchors.fill: parent
      radius: parent.radius
      from: root.pal.crab
      to: root.pal.limit
      running: chip.open || chipMouse.containsMouse
    }

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        textFormat: Text.PlainText
        color: chip.tone.a > 0 ? chip.tone : chip.quiet ? root.pal.muted : root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        d: "M6 9l6 6 6-6"
        size: Style.space(12)
        stroke: 2.4
        rotation: chip.open ? 180 : 0
        color: root.pal.muted
        Behavior on rotation { NumberAnimation { duration: 140 } }
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }

  component Segment: Rectangle {
    id: seg
    property string which: ""
    property string icon: ""
    property string label: ""
    readonly property bool on: root.mode === which

    width: segRow.implicitWidth + Style.space(12) * 2
    height: Style.space(26)
    radius: root.pal.pill(height)
    color: on ? root.pal.alpha(root.pal.fg, 0.14) : segMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.06) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      id: segRow
      anchors.centerIn: parent
      spacing: Style.space(6)

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        d: seg.icon
        size: Style.space(13)
        color: seg.on ? root.pal.crab : root.pal.muted
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: seg.label
        textFormat: Text.PlainText
        color: seg.on ? root.pal.strong : root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: seg.on
      }
    }

    MouseArea {
      id: segMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.picked(seg.which)
    }
  }
}
