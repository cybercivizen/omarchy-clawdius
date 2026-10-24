import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Apps.js" as Apps
import "Calc.js" as Calc
import "Icons.js" as Icons

// The search view, under the nav's search bar (BarWidget draws the bar and
// its chip). Nothing typed: a row of apps used lately and, past a divider,
// the default browser's recent tabs (tabs.py) as chips, ‹ › paging through
// the ones that don't fit. Typing: the installed
// apps that match, ↑↓ to pick, Enter to open; a sum is worked out above them
// (Enter copies it), and when no app matches, a Google search is offered.
// With the terminal chip (`/ `) Enter runs the text in a terminal; with the
// Google chip (`/g `) it searches Google in the default browser.
Item {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property string query: ""
  // "" | "terminal" | "google"
  property string chip: ""
  // id → {n, t}: BarWidget's app usage record.
  property var usage: ({})
  // {title, url, host, icon, at}, newest first: BarWidget reads them.
  property var tabs: []
  property double now: Date.now()
  property int selected: 0

  signal launched(var entry)
  signal command(string text)
  signal google(string text)
  signal copied(string text)
  signal tabOpened(var tab)

  readonly property bool suggesting: chip === "" && query.trim() === ""
  readonly property var openIds: {
    var ids = []
    var tops = ToplevelManager.toplevels.values || []
    for (var i = 0; i < tops.length; i++) {
      var e = DesktopEntries.heuristicLookup(tops[i].appId || "")
      if (e && ids.indexOf(e.id) < 0) ids.push(e.id)
    }
    return ids
  }
  // Not while hidden: it ranks every installed app, and `now` ticks each second.
  readonly property var results: !visible || chip !== "" ? []
    : suggesting ? Apps.suggested(DesktopEntries.applications.values || [], usage, openIds, now, 8)
    : Apps.search(DesktopEntries.applications.values || [], query, usage, now, 6)
  // Typed "/" or "/g" but no space yet: say what they turn into.
  readonly property bool commandHint: chip === "" && /^\/g?$/.test(query.trim())
  readonly property bool typing: visible && chip === "" && !suggesting && !commandHint
  // {value, text} when what's typed is a sum (Calc.js).
  readonly property var calc: typing ? Calc.evaluate(query) : null
  readonly property bool found: calc !== null || results.length > 0
  // What ↑↓ and Enter go through: the sum, the apps, or Google when there's
  // neither. Only the apps have an id of their own.
  readonly property var rows: !typing ? results
    : (calc ? [{ id: "calc:", kind: "calc", name: calc.text }] : [])
      .concat(results)
      .concat(found ? [] : [{ id: "google:", kind: "google", name: query.trim() }])

  // The results rebuild on every clock tick and app switch, not just on
  // typing: the pick stays on the same app until the query or chip changes.
  property string pickedId: ""
  property string pickedFor: ""

  onRowsChanged: {
    var at = -1
    if (pickedFor === chip + "\n" + query)
      for (var i = 0; i < rows.length; i++) if (rows[i].id === pickedId) { at = i; break }
    pick(at >= 0 ? at : 0)
  }

  function pick(i) {
    selected = i
    pickedId = rows[i] ? rows[i].id : ""
    pickedFor = chip + "\n" + query
  }

  // Rows are rebuilt under a resting pointer and get hover events of their
  // own; only a pointer that actually moved picks.
  property point hoverAt: Qt.point(-1, -1)
  function hovered(area, mouse, i) {
    var at = area.mapToItem(root, mouse.x, mouse.y)
    if (at.x === hoverAt.x && at.y === hoverAt.y) return
    hoverAt = at
    pick(i)
  }

  function move(delta) {
    if (!rows.length) return
    pick((selected + delta + rows.length) % rows.length)
  }

  // Enter: whatever the view is offering.
  function activate() {
    var text = query.trim()
    if (chip === "terminal") { if (text) root.command(text); return }
    if (chip === "google") { if (text) root.google(text); return }
    if (rows.length) open(rows[Math.min(selected, rows.length - 1)])
  }

  function open(row) {
    if (row.kind === "calc") root.copied(row.name)
    else if (row.kind === "google") root.google(row.name)
    else root.launched(row)
  }

  // The tab chips' › (1) and ‹ (-1).
  function pageTabs(delta) { tabStrip.page(delta) }

  function iconFor(entry) {
    var name = String(entry && entry.icon || "")
    if (name.charAt(0) === "/") return "file://" + name
    return Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true)
  }

  // ‹ or › over the tab chips' faded edge.
  component StripArrow: Rectangle {
    id: arrow
    property QtObject pal
    property string d
    property bool shown
    signal clicked()
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(26)
    height: width
    radius: width / 2
    color: arrowMouse.containsMouse ? arrow.pal.alpha(arrow.pal.fg, 0.16) : arrow.pal.alpha(arrow.pal.fg, 0.09)
    border.width: 1
    border.color: arrow.pal.alpha(arrow.pal.fg, 0.10)
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 140 } }
    Behavior on color { ColorAnimation { duration: 100 } }

    Icon {
      anchors.centerIn: parent
      d: arrow.d
      size: Style.space(14)
      color: arrowMouse.containsMouse ? arrow.pal.strong : arrow.pal.fg
    }

    MouseArea {
      id: arrowMouse
      anchors.fill: parent
      enabled: arrow.shown
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: arrow.clicked()
    }
  }

  implicitHeight: column.implicitHeight

  Column {
    id: column
    width: parent.width
    spacing: Style.space(8)

    // ---- Nothing typed: apps used lately, one row, then the recent tabs.
    Item {
      visible: root.suggesting
      width: parent.width
      height: apps.height

      Row {
        id: apps
        x: Style.space(4)
        spacing: Style.space(4)

        Repeater {
          model: root.suggesting ? root.results : []

          Rectangle {
            id: tile
            required property var modelData
            required property int index
            readonly property bool on: index === root.selected
            width: Style.space(70)
            height: Style.space(76)
            radius: pal.rad(Style.space(16))
            color: on ? root.pal.alpha(root.pal.fg, 0.10) : tileMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }

            Image {
              anchors.horizontalCenter: parent.horizontalCenter
              y: Style.space(10)
              width: Style.space(36)
              height: width
              sourceSize: Qt.size(width * 2, height * 2)
              source: root.iconFor(tile.modelData)
              asynchronous: true
              smooth: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              y: Style.space(52)
              width: parent.width - Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              text: tile.modelData.name
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: tile.on ? root.pal.strong : root.pal.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: function(mouse) { root.hovered(tileMouse, mouse, tile.index) }
              onClicked: root.launched(tile.modelData)
            }
          }
        }
      }

      // Where the apps end: a divider, then the browser's tabs, two rows of
      // chips filled a column at a time. What doesn't fit fades out to
      // nothing at the edge, so it's the island behind in either theme;
      // › pages a column on, and ‹ comes up to page back.
      Rectangle {
        id: divider
        visible: tabStrip.visible
        x: apps.x + apps.width + Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        width: 1
        height: parent.height - Style.space(16)
        color: root.pal.hairline
      }

      Item {
        id: tabStrip
        x: divider.x + Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - Style.space(4)
        visible: root.tabs.length > 0 && width >= Style.space(90)
        readonly property real chipHeight: Style.space(30)
        height: chipHeight * 2 + tabFlow.spacing
        clip: true

        // How far it's paged, in px; back to the start each time it shows.
        property real offset: 0
        readonly property real maxOffset: Math.max(0, tabFlow.childrenRect.width - width)
        readonly property bool canLeft: offset > 1
        readonly property bool canRight: offset < maxOffset - 1
        readonly property real fade: Style.space(72)
        Behavior on offset { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Connections {
          target: root
          function onSuggestingChanged() { tabStrip.offset = 0 }
          function onTabsChanged() { tabStrip.offset = 0 }
        }

        // Where each column of chips starts.
        function columns() {
          var xs = []
          for (var i = 0; i < tabFlow.children.length; i++) {
            var c = tabFlow.children[i]
            if (c.width > 0 && xs.indexOf(c.x) < 0) xs.push(c.x)
          }
          return xs.sort(function(a, b) { return a - b })
        }
        function page(delta) {
          var xs = columns(), to = delta > 0 ? maxOffset : 0
          if (delta > 0) { for (var i = 0; i < xs.length; i++) if (xs[i] > offset + 1) { to = xs[i]; break } }
          else { for (var j = xs.length - 1; j >= 0; j--) if (xs[j] < offset - 1) { to = xs[j]; break } }
          offset = Math.max(0, Math.min(maxOffset, to))
        }

        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: function(event) {
            var d = event.angleDelta.x || event.angleDelta.y
            if (d) tabStrip.page(d < 0 ? 1 : -1)
          }
        }

        Item {
          id: chips
          anchors.fill: parent
          layer.enabled: true
          // 0.5 spread by 1: the chips' alpha follows the mask's, softly
          // (a threshold of 0 would keep any alpha above it opaque).
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fadeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
          }

          Flow {
            id: tabFlow
            x: -tabStrip.offset
            height: parent.height
            flow: Flow.TopToBottom
            spacing: Style.space(6)

            Repeater {
              model: root.suggesting ? root.tabs.slice(0, 5) : []

              Rectangle {
                id: tabChip
                required property var modelData
                width: Math.min(tabRow.implicitWidth + Style.space(10) * 2, tabStrip.width)
                height: tabStrip.chipHeight
                radius: pal.pill(height)
                color: tabMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.12) : root.pal.alpha(root.pal.fg, 0.06)
                border.width: 1
                border.color: tabMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.16) : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Row {
                  id: tabRow
                  x: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(7)

                  Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(16)
                    height: width

                    Image {
                      id: favicon
                      anchors.fill: parent
                      sourceSize: Qt.size(width * 2, height * 2)
                      source: tabChip.modelData.icon || ""
                      asynchronous: true
                      smooth: true
                    }
                    // No favicon: the site's initial in a dot.
                    Rectangle {
                      visible: favicon.status !== Image.Ready
                      anchors.fill: parent
                      radius: width / 2
                      color: root.pal.alpha(root.pal.crab, 0.22)
                      Text {
                        anchors.centerIn: parent
                        text: (tabChip.modelData.host || "?").charAt(0).toUpperCase()
                        textFormat: Text.PlainText
                        color: root.pal.crab
                        font.family: root.fontFamily
                        font.pixelSize: Math.round(Style.font.caption * 0.9)
                        font.bold: true
                      }
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, Style.space(150), tabStrip.width - Style.space(10) * 2 - Style.space(23))
                    text: tabChip.modelData.title
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: tabMouse.containsMouse ? root.pal.strong : root.pal.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: tabMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.tabOpened(tabChip.modelData)
                }
              }
            }
          }
        }

        // Opaque in the middle, clear at an edge with more past it.
        Item {
          id: fadeMask
          anchors.fill: parent
          visible: false
          layer.enabled: true
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: tabStrip.canLeft ? "transparent" : "white" }
              GradientStop { position: Math.min(0.45, tabStrip.fade / Math.max(1, tabStrip.width)); color: "white" }
              GradientStop { position: Math.max(0.55, 1 - tabStrip.fade / Math.max(1, tabStrip.width)); color: "white" }
              GradientStop { position: 1; color: tabStrip.canRight ? "transparent" : "white" }
            }
          }
        }

        StripArrow { pal: root.pal; anchors.left: parent.left; shown: tabStrip.canLeft; d: Icons.back; onClicked: tabStrip.page(-1) }
        StripArrow { pal: root.pal; anchors.right: parent.right; shown: tabStrip.canRight; d: Icons.forward; onClicked: tabStrip.page(1) }
      }
    }

    // ---- Typing: the sum, the apps that match, or else Google.
    Column {
      visible: root.typing
      width: parent.width
      spacing: Style.space(2)

      Repeater {
        model: root.typing ? root.rows : []

        Rectangle {
          id: row
          required property var modelData
          required property int index
          readonly property bool on: index === root.selected
          width: parent.width
          height: Style.space(44)
          radius: pal.rad(Style.space(14))
          color: on ? root.pal.alpha(root.pal.fg, 0.10) : rowMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.05) : "transparent"

          readonly property string kind: modelData.kind || "app"

          Item {
            id: rowIcon
            x: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(26)
            height: width

            Image {
              visible: row.kind === "app"
              anchors.fill: parent
              sourceSize: Qt.size(width * 2, height * 2)
              source: row.kind === "app" ? root.iconFor(row.modelData) : ""
              asynchronous: true
              smooth: true
            }
            Text {
              visible: row.kind === "calc"
              anchors.centerIn: parent
              text: "="
              textFormat: Text.PlainText
              color: root.pal.crab
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            GoogleMark {
              visible: row.kind === "google"
              anchors.centerIn: parent
              size: Style.space(18)
            }
          }

          Text {
            id: rowName
            anchors.left: rowIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.5)
            text: row.modelData.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.pal.strong
            font.family: root.fontFamily
            font.pixelSize: row.kind === "calc" ? Style.font.subtitle : Style.font.body
            font.bold: row.on || row.kind === "calc"
          }

          Text {
            anchors.left: rowName.right
            anchors.leftMargin: Style.space(10)
            anchors.right: enterHint.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            text: row.kind === "calc" ? root.query.trim()
              : row.kind === "google" ? "No apps match. Search Google for it"
              : row.modelData.genericName || row.modelData.comment || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.pal.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            id: enterHint
            anchors.right: parent.right
            anchors.rightMargin: Style.space(14)
            anchors.verticalCenter: parent.verticalCenter
            visible: row.on
            text: row.kind === "calc" ? "↵ copy" : row.kind === "google" ? "↵ search" : "↵ open"
            textFormat: Text.PlainText
            color: root.pal.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(mouse) { root.hovered(rowMouse, mouse, row.index) }
            onClicked: root.open(row.modelData)
          }
        }
      }

      Text {
        visible: !root.found
        x: Style.space(12)
        height: Style.space(32)
        verticalAlignment: Text.AlignVCenter
        text: "Or start with / to run it in a terminal."
        textFormat: Text.PlainText
        color: root.pal.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    // ---- A chip set, or about to be: what Enter will do.
    Rectangle {
      visible: root.chip !== "" || root.commandHint
      width: parent.width
      height: Style.space(48)
      radius: pal.rad(Style.space(14))
      color: root.pal.alpha(root.pal.fg, 0.05)

      Row {
        x: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(10)

        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18)
          height: width
          Icon {
            visible: root.chip !== "google"
            anchors.centerIn: parent
            d: root.chip === "" ? Icons.search : Icons.terminal
            size: Style.space(16)
            color: root.pal.crab
          }
          GoogleMark {
            visible: root.chip === "google"
            anchors.centerIn: parent
            size: Style.space(16)
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.chip === "terminal"
              ? (root.query.trim() ? "Enter runs it in a new terminal" : "Type a command; Enter runs it in a new terminal")
            : root.chip === "google"
              ? (root.query.trim() ? "Enter searches Google in your browser" : "Type what to search for; Enter opens Google")
            : "Space after / for a terminal command, after /g for a Google search"
          textFormat: Text.PlainText
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        visible: root.chip !== ""
        text: "⌫ on empty removes it"
        textFormat: Text.PlainText
        color: root.pal.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      visible: root.suggesting
      x: Style.space(8)
      text: "Type to find an app or work out a sum  ·  / runs a command  ·  /g searches Google  ·  Esc closes"
      textFormat: Text.PlainText
      color: root.pal.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
