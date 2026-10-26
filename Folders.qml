import QtQuick
import Quickshell
import qs.Commons

// The Folders tab: directories Claude worked in lately, newest first. Click
// one to list its sessions, a line each (title, then the start of the last
// reply); click a session to open it in the live terminal, or + New session for a
// fresh one there. The Chat and Code folders are left out, since their
// buttons already open there.
Column {
  id: root

  // Each: {cwd, mtime, count, title, sessions: [resumable entries, newest first]}.
  property QtObject pal
  property var folders: []
  // Session id → "busy" | "waiting" | "idle" for the ones running now.
  property var running: ({})
  // Session id → ms the sweep put it to sleep.
  property var asleep: ({})
  property double now: Date.now()
  property color fg: Color.foreground
  property color mutedFg: Qt.darker(fg, 1.45)
  property color accent: "#D97757"
  property string fontFamily: Style.font.family
  // The folder (or session id) whose session is being started, if any.
  property string starting: ""
  // Sessions listed per open folder before "Show all".
  property int sessionLimit: 10

  // Folders whose sessions are listed, and those showing every session.
  property var expanded: ({})
  property var showAll: ({})

  // + New on a folder: start a new session there.
  signal activated(string cwd)
  // A session in an open folder was clicked.
  signal sessionActivated(var session)

  spacing: Style.space(2)

  function ago(sec) {
    var m = Math.max(1, Math.round((root.now / 1000 - sec) / 60))
    if (m < 60) return m + "m"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h"
    if (h < 24 * 7) return Math.floor(h / 24) + "d"
    var d = new Date(sec * 1000)
    var thisYear = d.getFullYear() === new Date(root.now).getFullYear()
    return Qt.formatDate(d, thisYear ? "MMM d" : "MMM d yyyy")
  }

  function folder(cwd) {
    var home = Quickshell.env("HOME")
    if (cwd === home) return "~"
    return cwd.indexOf(home + "/") === 0 ? "~/" + cwd.slice(home.length + 1) : cwd
  }

  function flip(map, key) {
    var next = {}
    for (var k in map) next[k] = map[k]
    next[key] = !next[key]
    return next
  }
  // Under the folder (beside it in the dense look): how many sessions, and the last one.
  function summary(f, open) {
    return f.count + (f.count > 1 ? " sessions" : " session")
      + (f.cwd === Quickshell.env("HOME") ? " · open in a terminal (Claude won't run them in the background here)"
         : open ? "" : f.title ? " · last: " + f.title : "")
  }

  Text {
    visible: root.folders.length === 0
    width: parent.width
    topPadding: root.pal.sp(6)
    bottomPadding: root.pal.sp(6)
    horizontalAlignment: Text.AlignHCenter
    text: "No other folders yet."
    textFormat: Text.PlainText
    color: root.mutedFg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.folders

    Item {
      id: row
      required property var modelData
      readonly property real padH: root.pal.sp(10)
      readonly property real padV: root.pal.sp(6)
      readonly property bool starting: root.starting !== "" && root.starting === modelData.cwd
      readonly property bool open: !!root.expanded[modelData.cwd]
      readonly property bool all: !!root.showAll[modelData.cwd]
      readonly property var listed: open ? (all ? modelData.sessions : modelData.sessions.slice(0, root.sessionLimit)) : []
      width: root.width
      height: rowColumn.implicitHeight + padV * 2

      Rectangle {
        anchors.fill: parent
        radius: pal.rad(Style.space(12))
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, row.open ? 0.05 : headMouse.containsMouse ? 0.07 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      Column {
        id: rowColumn
        x: row.padH
        y: row.padV
        width: parent.width - row.padH * 2
        spacing: Style.space(2)

        // ---- The folder: click to list its sessions
        Item {
          width: parent.width
          height: headColumn.implicitHeight

          MouseArea {
            id: headMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded = root.flip(root.expanded, row.modelData.cwd)
          }

          Column {
            id: headColumn
            width: parent.width
            spacing: Style.space(2)

            Item {
              width: parent.width
              height: Math.max(dirText.implicitHeight, newButton.height)

              Text {
                id: chevron
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(14)
                text: row.open ? "▾" : "▸"
                textFormat: Text.PlainText
                color: root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: dirText
                anchors.left: chevron.right
                anchors.right: root.pal.dense ? undefined : newButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: root.pal.dense ? Math.min(implicitWidth, parent.width * 0.4) : undefined
                text: root.folder(row.modelData.cwd)
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: row.starting ? root.accent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                visible: root.pal.dense
                anchors.left: dirText.right
                anchors.leftMargin: Style.space(8)
                anchors.right: newButton.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.summary(row.modelData, row.open)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: newButton
                anchors.right: whenText.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: newText.implicitWidth + Style.space(14)
                height: newText.implicitHeight + Style.space(4)
                radius: pal.pill(height)
                visible: headMouse.containsMouse || newMouse.containsMouse || row.starting
                color: newMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : "transparent"
                border.width: 1
                border.color: newMouse.containsMouse ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

                Text {
                  id: newText
                  anchors.centerIn: parent
                  text: row.starting ? "starting…" : "+ New session"
                  textFormat: Text.PlainText
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                MouseArea {
                  id: newMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: root.starting === ""
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.activated(row.modelData.cwd)
                }
              }

              Text {
                id: whenText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.ago(row.modelData.mtime)
                textFormat: Text.PlainText
                color: root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              visible: !root.pal.dense
              x: Style.space(14)
              width: parent.width - x
              text: root.summary(row.modelData, row.open)
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: root.mutedFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // ---- Its sessions, a line each
        Column {
          visible: row.open
          x: Style.space(8)
          width: parent.width - x
          topPadding: Style.space(4)
          spacing: 0

          Repeater {
            model: row.listed

            Item {
              id: line
              required property var modelData
              readonly property string state_: root.running[modelData.id] || ""
              readonly property bool opening: root.starting !== "" && root.starting === modelData.id
              // Stopped by the sweep, and not touched since.
              readonly property bool sleeping: !state_ && !!root.asleep[modelData.id] && modelData.mtime * 1000 <= root.asleep[modelData.id] + 10000
              width: parent.width
              height: lineTitle.implicitHeight + Style.space(8)

              Rectangle {
                anchors.fill: parent
                radius: pal.rad(Style.space(8))
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, lineMouse.containsMouse ? 0.08 : 0)
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              MouseArea {
                id: lineMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: root.starting === ""
                cursorShape: Qt.PointingHandCursor
                onClicked: root.sessionActivated(line.modelData)
              }

              // Running ones get a dot, like the Tasks tab's.
              Rectangle {
                id: lineDot
                x: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(5)
                height: width
                radius: width / 2
                color: line.state_ === "idle" ? root.mutedFg : root.accent
                opacity: line.state_ ? 1 : 0
              }

              Text {
                id: lineTitle
                anchors.left: lineDot.right
                anchors.leftMargin: Style.space(7)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, (parent.width - lineWhen.width) * 0.45)
                text: line.modelData.title
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: line.opening ? root.accent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                anchors.left: lineTitle.right
                anchors.leftMargin: Style.space(8)
                anchors.right: lineWhen.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: line.modelData.summary || ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                id: lineWhen
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: line.opening ? "opening…"
                  : line.state_ === "busy" ? "working"
                  : line.state_ === "waiting" ? "needs you"
                  : line.state_ ? "running"
                  : line.sleeping ? "asleep · " + root.ago(line.modelData.mtime)
                  : root.ago(line.modelData.mtime)
                textFormat: Text.PlainText
                color: line.opening || line.state_ === "busy" || line.state_ === "waiting" ? root.accent : root.mutedFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            visible: row.modelData.sessions.length > root.sessionLimit
            x: Style.space(18)
            topPadding: Style.space(3)
            bottomPadding: Style.space(2)
            text: row.all ? "Show fewer" : "Show all " + row.modelData.sessions.length
            textFormat: Text.PlainText
            color: moreMouse.containsMouse ? root.fg : root.mutedFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption

            MouseArea {
              id: moreMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showAll = root.flip(root.showAll, row.modelData.cwd)
            }
          }
        }
      }
    }
  }
}
