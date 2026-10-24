import QtQuick
import Quickshell
import qs.Commons
import "Format.js" as Format
import "Icons.js" as Icons

// What + opens, on every view: always a new session. Side by side up top,
// Code (in ~/Work, auto mode) and Chat (~/chat, talk only) start in the
// island's live view and Web opens claude.ai; then Code in one of the last
// few folders Claude worked in, or all of them (Sessions → Folders), or in
// any folder: one picked from disk, a new one, or a repo cloned for it.
Rectangle {
  id: root

  property QtObject pal
  property string fontFamily: Style.font.family
  property string codeDir: ""
  property string chatDir: ""
  // recentFolders entries: {cwd, mtime, …}
  property var folders: []
  property double now: Date.now()

  signal launched(string which)
  signal folderPicked(string cwd)
  signal allFolders()
  // "open" (pick an existing folder) or "new" (make one).
  signal browse(string how)
  signal cloneRepo()

  readonly property string home: Quickshell.env("HOME") || ""

  function when(sec) {
    var days = Math.floor((root.now / 1000 - sec) / 86400)
    return days < 1 ? "today" : days < 2 ? "yesterday" : days + "d ago"
  }

  width: Style.space(320)
  height: column.implicitHeight + Style.space(8) * 2
  radius: pal.rad(Style.space(20))
  color: pal.raised
  border.width: 1
  border.color: pal.line

  Column {
    id: column
    x: Style.space(8)
    y: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(2)

    Row {
      width: parent.width
      spacing: Style.space(4)

      Tile { icon: Icons.code; accent: true; label: "Code"; tip: Format.folder(root.codeDir, root.home) + " · auto mode"; onClicked: root.launched("code") }
      Tile { icon: Icons.chat; accent: true; label: "Chat"; tip: Format.folder(root.chatDir, root.home) + " · talk only"; onClicked: root.launched("chat") }
      Tile { icon: Icons.external; label: "Web"; tip: "claude.ai in the browser"; onClicked: root.launched("web") }
    }

    Item { width: 1; height: Style.space(4) }

    Rectangle {
      width: parent.width - Style.space(16)
      x: Style.space(8)
      height: 1
      color: root.pal.alpha(root.pal.fg, 0.08)
    }

    Text {
      leftPadding: Style.space(12)
      topPadding: Style.space(8)
      bottomPadding: Style.space(2)
      text: "CODE IN A FOLDER"
      textFormat: Text.PlainText
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.8
    }

    Repeater {
      model: root.folders.slice(0, 3)
      MenuItem {
        required property var modelData
        compact: true
        icon: Icons.folder
        label: Format.folder(modelData.cwd, root.home)
        side: root.when(modelData.mtime)
        onClicked: root.folderPicked(modelData.cwd)
      }
    }

    MenuItem {
      visible: root.folders.length > 0
      compact: true
      label: "All folders…"
      quiet: true
      onClicked: root.allFolders()
    }

    MenuItem { compact: true; icon: Icons.folder; label: "Open folder…"; quiet: true; onClicked: root.browse("open") }
    MenuItem { compact: true; icon: Icons.folderPlus; label: "New folder…"; quiet: true; onClicked: root.browse("new") }
    MenuItem { compact: true; icon: Icons.clone; label: "Clone repo…"; quiet: true; onClicked: root.cloneRepo() }
  }

  // The hovered tile's tip, in a bubble just under it.
  property Item tipFor: null

  Rectangle {
    id: tipBubble
    readonly property point at: root.tipFor ? root.tipFor.mapToItem(root, root.tipFor.width / 2, root.tipFor.height) : Qt.point(0, 0)
    visible: root.tipFor !== null
    z: 10
    x: Math.max(Style.space(4), Math.min(root.width - width - Style.space(4), at.x - width / 2))
    y: at.y + Style.space(4)
    width: tipText.implicitWidth + Style.space(10) * 2
    height: tipText.implicitHeight + Style.space(5) * 2
    radius: pal.pill(height)
    color: root.pal.raised
    border.width: 1
    border.color: root.pal.line

    Text {
      id: tipText
      anchors.centerIn: parent
      text: root.tipFor ? root.tipFor.tip : ""
      textFormat: Text.PlainText
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Code / Chat / Web: an icon and its name, three abreast in one slim row;
  // where it goes shows in the tip on hover.
  component Tile: Rectangle {
    id: tile
    property string icon: ""
    property bool accent: false
    property string label: ""
    property string tip: ""
    signal clicked()

    width: (column.width - Style.space(4) * 2) / 3
    height: Style.space(36)
    radius: root.pal.rad(Style.space(12))
    color: tileMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.08) : root.pal.alpha(root.pal.fg, 0.03)

    Row {
      anchors.centerIn: parent
      spacing: Style.space(8)

      Icon {
        anchors.verticalCenter: parent.verticalCenter
        d: tile.icon
        size: Style.space(15)
        color: tile.accent ? root.pal.crab : root.pal.fg
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: tile.label
        textFormat: Text.PlainText
        color: root.pal.strong
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: {
        if (containsMouse) root.tipFor = tile
        else if (root.tipFor === tile) root.tipFor = null
      }
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.clicked()
    }
  }

  component MenuItem: Rectangle {
    id: item
    property string icon: ""
    property bool accent: false
    property string label: ""
    property string sub: ""
    property string side: ""
    property bool compact: false
    property bool quiet: false
    signal clicked()

    width: column.width
    height: Style.space(compact ? 34 : 46)
    radius: root.pal.rad(Style.space(12))
    color: itemMouse.containsMouse ? root.pal.alpha(root.pal.fg, 0.08) : "transparent"

    Row {
      x: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(24)
      spacing: Style.space(12)

      Icon {
        visible: item.icon !== ""
        anchors.verticalCenter: parent.verticalCenter
        d: item.icon
        size: Style.space(item.compact ? 14 : 16)
        color: item.accent ? root.pal.crab : item.compact ? root.pal.muted : root.pal.fg
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - sideText.implicitWidth - Style.space(8)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: item.label
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          color: item.quiet ? root.pal.muted : item.compact ? root.pal.fg : root.pal.strong
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: !item.compact
        }

        Text {
          visible: item.sub !== ""
          width: parent.width
          text: item.sub
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: root.pal.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    Text {
      id: sideText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: item.side
      textFormat: Text.PlainText
      color: root.pal.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: itemMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: item.clicked()
    }
  }
}
