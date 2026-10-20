import QtQuick
import Quickshell
import qs.Commons

// Sessions → Recent: Claude Code conversations that are not running right
// now, newest first, each marked with whether resuming it now hits the
// prompt cache or sends the whole context again. The first few show, then
// the rest a page at a time; ones whose folder is gone are listed but can't
// be resumed.
Column {
  id: root

  property var sessions: []
  property double now: Date.now()
  property color fg: Color.foreground
  property color mutedFg: Qt.darker(fg, 1.45)
  property color accent: "#D97757"
  property string fontFamily: Style.font.family
  property string emptyText: "No earlier sessions to resume."
  // Rows shown before "Show more" (firstPage), and how many more each click
  // shows (pageSize); 0 shows them all.
  property int pageSize: 0
  property int firstPage: pageSize
  property int shown: firstPage
  // Nothing while hidden: each feed update hands over a new list, and the
  // Repeater rebuilds every row for it.
  readonly property var visibleSessions: !visible ? [] : pageSize > 0 ? sessions.slice(0, shown) : sessions
  onSessionsChanged: if (pageSize > 0 && shown > sessions.length) shown = Math.max(firstPage, sessions.length)

  // A row was clicked: reopen that session in its own directory.
  signal activated(var session)

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

  function tokens(n) {
    if (n < 1000) return n + " tok"
    if (n < 10000) return (n / 1000).toFixed(1) + "k tok"
    return Math.round(n / 1000) + "k tok"
  }

  function family(model) {
    var parts = (model || "").split("-")
    return parts.length > 1 ? parts[1].charAt(0).toUpperCase() + parts[1].slice(1) : model
  }

  // Seconds of cache left, or 0 once it has expired or the model differs.
  function cacheLeft(s) {
    if (!s.sameModel || !s.lastCall) return 0
    return Math.max(0, s.lastCall + s.ttl - Math.floor(root.now / 1000))
  }

  function cacheText(s) {
    var left = cacheLeft(s)
    if (left > 0) return "cached · " + (left < 60 ? left + "s" : Math.ceil(left / 60) + "m") + " left"
    if (!s.tokens) return ""
    return "reloads " + tokens(s.tokens) + (s.sameModel ? "" : " · was " + family(s.model))
  }

  function folder(cwd) {
    var home = Quickshell.env("HOME")
    if (cwd === home) return "~"
    return cwd.indexOf(home + "/") === 0 ? "~/" + cwd.slice(home.length + 1) : cwd
  }

  Text {
    visible: root.sessions.length === 0
    width: parent.width
    topPadding: Style.space(6)
    bottomPadding: Style.space(6)
    horizontalAlignment: Text.AlignHCenter
    text: root.emptyText
    textFormat: Text.PlainText
    color: root.mutedFg
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Repeater {
    model: root.visibleSessions

    Item {
      id: row
      required property var modelData
      readonly property real padH: Style.space(10)
      readonly property real padV: Style.space(6)
      width: root.width
      height: rowColumn.implicitHeight + padV * 2

      Rectangle {
        anchors.fill: parent
        radius: Style.space(12)
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, rowMouse.containsMouse ? 0.07 : 0)
        Behavior on color { ColorAnimation { duration: 120 } }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !row.modelData.missing
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated(row.modelData)
      }

      Column {
        id: rowColumn
        opacity: row.modelData.missing ? 0.5 : 1
        x: row.padH
        y: row.padV
        width: parent.width - row.padH * 2
        spacing: Style.space(2)

        Item {
          width: parent.width
          height: titleText.implicitHeight

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.right: whenText.left
            anchors.rightMargin: Style.space(8)
            text: row.modelData.title
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: whenText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.ago(row.modelData.mtime)
            color: root.mutedFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          readonly property bool cached: root.cacheLeft(row.modelData) > 0
          width: parent.width
          height: folderText.implicitHeight

          Text {
            id: folderText
            anchors.left: parent.left
            anchors.right: cacheText.left
            anchors.rightMargin: Style.space(8)
            text: row.modelData.missing ? (row.modelData.cwd ? root.folder(row.modelData.cwd) + " · folder gone" : "folder unknown")
              : root.folder(row.modelData.cwd)
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: root.mutedFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            id: cacheText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.cacheText(row.modelData)
            textFormat: Text.PlainText
            color: parent.cached ? root.accent : root.mutedFg
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  Item {
    visible: root.pageSize > 0 && root.sessions.length > root.shown
    width: parent.width
    height: moreText.implicitHeight + Style.space(12)

    Text {
      id: moreText
      anchors.centerIn: parent
      text: "Show " + Math.min(root.pageSize, root.sessions.length - root.shown) + " more  ·  "
        + (root.sessions.length - root.shown) + " left"
      textFormat: Text.PlainText
      color: moreMouse.containsMouse ? root.fg : root.mutedFg
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: moreMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.shown += root.pageSize
    }
  }
}
