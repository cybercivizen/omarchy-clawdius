import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons

// The shell's PopupCard, reworked for the crab: a see-through surface that
// Hyprland frosts (decoration.blur.popups), a sheen and hairline edge for the
// glass, and a drop-in that eases down from the bar instead of a plain fade.
//
// As an island (`island: true`) it hangs straight off the bar instead: square
// corners against the bar, a wide radius on the free ones, no glass sheen.
//
// The window itself is sized for the widest and tallest card the screen
// allows and stays put; the surface inside grows and shrinks, so view
// switches and approvals animate without resizing the Wayland popup (a
// resize shows a frame of the old buffer squashed into the new size). The
// input mask follows the surface, so the empty part never eats clicks.
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  // The edge against the bar; the island's nav sits close under it.
  property int barPadding: padding
  property bool island: false
  property real islandRadius: Style.space(30)
  property int contentWidth: Style.space(280)
  property int maxContentWidth: contentWidth
  property int contentHeight: Style.space(200)
  property int maxContentHeight: contentHeight
  property bool open: false
  // Open without taking the bar's popout slot (the crab's notification
  // peek): another panel that's up stays up. Claimed once this goes false.
  property bool passive: false
  // Off while something inside resizes all the time (the live terminal),
  // where easing the card's height after it only clips the bottom.
  property bool animateHeight: true
  // How long a height change eases for; longer for a big jump (into the live view).
  property int heightDuration: 240
  // More surfaces that count as "inside" for the focus grab (the crab's key window).
  property var grabWindows: []
  property bool centerOnBar: false
  property string triggerMode: "click"
  // How much of the theme's popup background is left once frosted.
  property real frostAlpha: 0.62
  property color tint: Commons.Color.popups.background
  property color edge: Commons.Color.foreground

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: cardHover.hovered || floatHover.hovered
  // Where the drawn surface is, in the bar window's coordinates.
  readonly property rect surfaceRect: Qt.rect(popupAnchor.rect.x + maskBox.x, popupAnchor.rect.y + maskBox.y, maskBox.width, maskBox.height)
  // Over the surface and not clipped by it, the window's size: a menu put
  // here can hang past the island's edge into the window's empty part.
  // floatMask (an item in it) joins the input mask; floatRect is where it is,
  // in the bar window's coordinates.
  readonly property Item floatLayer: floatHolder
  property Item floatMask: null
  readonly property rect floatRect: floatMask && !tucked
    ? Qt.rect(popupAnchor.rect.x + floatMask.x, popupAnchor.rect.y + floatMask.y, floatMask.width, floatMask.height)
    : Qt.rect(0, 0, 0, 0)
  // Out of the way of a window that has to be over it (a file chooser: no
  // window goes above the bar's layer): undrawn and click-through, still open.
  property bool tucked: false
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding + barPadding
  readonly property bool fromBottom: !!bar && bar.position === "bottom"

  // 0 closed → 1 open. Opening springs out slowly, closing gets out of the way.
  // The island runs it linearly and shapes each part of its morph itself.
  // Started from onOpenChanged rather than a Behavior: a Behavior could start
  // before its duration binding saw the new `open`, so closing ran at the
  // opening's speed.
  property real progress: 0
  NumberAnimation {
    id: progressAnim
    target: root
    property: "progress"
  }

  // The island grows out of the bar: a sliver under it widens, then drops
  // to full height, and the content fades in once the shape has landed.
  // Closing runs the same path back into the bar, content first.
  function span(p, from, to) { return Math.max(0, Math.min(1, (p - from) / (to - from))) }
  function outQuint(t) { return 1 - Math.pow(1 - t, 5) }
  function outCubic(t) { return 1 - Math.pow(1 - t, 3) }
  // (Closing runs progress back down, so its curves read right to left:
  // content out first, then the height folds up, then the width. The
  // height drops most of the way at once and eases into the bar.)
  readonly property real islandWidthT: root.open ? outQuint(span(progress, 0, 0.6)) : outCubic(span(progress, 0, 0.5))
  readonly property real islandHeightT: root.open ? outQuint(span(progress, 0.06, 1)) : Math.pow(span(progress, 0.04, 0.92), 2)
  readonly property real islandContentT: root.open ? outCubic(span(progress, 0.32, 0.85)) : span(progress, 0.7, 1)
  readonly property real islandStartWidth: Math.min(contentWidth, Style.space(200))
  readonly property real islandStartHeight: Style.space(8)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open || progress > 0
  color: "transparent"
  implicitWidth: Math.max(contentWidth, maxContentWidth)
  implicitHeight: Math.max(contentHeight, maxContentHeight)
  // The mask follows an untransformed twin of the surface: Region maps the
  // item when its geometry changes, not its scale, so masking the surface
  // itself froze the drop-in's 0.94 scale and left its edges dead to the
  // pointer (the card closed while you were still on its padding).
  mask: Region {
    item: root.tucked ? null : maskBox
    Region { item: root.floatMask && !root.tucked ? root.floatMask : null }
  }

  onOpenChanged: {
    progressAnim.stop()
    progressAnim.duration = root.island ? (open ? 540 : 200) : (open ? 380 : 170)
    progressAnim.easing.type = root.island ? Easing.Linear : open ? Easing.OutQuint : Easing.InCubic
    progressAnim.to = open ? 1 : 0
    progressAnim.start()
    if (!bar) return
    if (open && !passive) bar.requestPopout(coordinatorKey)
    else if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }
  onPassiveChanged: if (bar && open && !passive) bar.requestPopout(coordinatorKey)

  HyprlandFocusGrab {
    active: root.open && root.triggerMode === "click"
    windows: (root.anchorWindow ? [root, root.anchorWindow] : [root]).concat(root.grabWindows)
    onCleared: root.close()
  }

  anchor {
    id: popupAnchor
    window: anchorItem ? anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return
      var target = root.anchorItem
      var window = target.QsWindow.window
      if (!window) return
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight

      if (root.centerOnBar && (root.bar.position === "top" || root.bar.position === "bottom")) {
        var cx = window.width / 2 - popupWidth / 2
        cx = Math.max(root.margin, Math.min(cx, window.width - popupWidth - root.margin))
        popupAnchor.rect.x = Math.round(cx)
        var gap = root.island ? 0 : root.margin
        popupAnchor.rect.y = Math.round(root.fromBottom ? -popupHeight - gap : window.height + gap)
        return
      }

      var localX = target.width / 2 - popupWidth / 2
      var localY = root.fromBottom ? -popupHeight - root.margin : target.height + root.margin
      if (root.bar.position === "left") { localX = target.width + root.margin; localY = target.height / 2 - popupHeight / 2 }
      else if (root.bar.position === "right") { localX = -popupWidth - root.margin; localY = target.height / 2 - popupHeight / 2 }
      var point = window.contentItem.mapFromItem(target, localX, localY)
      if (root.bar.position === "top" || root.bar.position === "bottom")
        point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
      else
        point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  // The island's final size while it morphs, so surfaceRect (the input mask,
  // the key window's hole, the bar's strip) holds still instead of changing
  // every frame of the open.
  Item {
    id: maskBox
    readonly property bool morphing: root.island && root.progress < 1
    width: morphing ? root.contentWidth : surface.width
    height: morphing ? root.contentHeight : surface.height
    x: (root.width - width) / 2
    y: root.fromBottom ? root.height - height : 0
  }

  Rectangle {
    id: surface
    visible: !root.tucked
    width: root.island && root.progress < 1
      ? root.islandStartWidth + (root.contentWidth - root.islandStartWidth) * root.islandWidthT
      : root.contentWidth
    x: (parent.width - width) / 2
    // Hug the bar's edge: top bars grow downwards, bottom bars upwards.
    y: root.fromBottom ? parent.height - height : 0
    height: root.island && root.progress < 1
      ? root.islandStartHeight + (root.contentHeight - root.islandStartHeight) * root.islandHeightT
      : root.contentHeight
    // A sliver is a pill; the full island has its 30 px corners.
    radius: root.island ? Math.min(root.islandRadius, height / 2) : Math.max(Style.cornerRadius, Style.space(14))
    topLeftRadius: root.island && !root.fromBottom ? 0 : radius
    topRightRadius: root.island && !root.fromBottom ? 0 : radius
    bottomLeftRadius: root.island && root.fromBottom ? 0 : radius
    bottomRightRadius: root.island && root.fromBottom ? 0 : radius
    color: Qt.rgba(root.tint.r, root.tint.g, root.tint.b, root.frostAlpha)
    border.width: root.island ? 0 : 1
    border.color: Qt.rgba(root.edge.r, root.edge.g, root.edge.b, 0.16)
    clip: true

    // Hyprland's blur switches on at full strength as soon as the glass is
    // barely there, so a slow fade-in reads as an empty frosted box for a
    // beat. Opening starts the glass already visible and lets the scale and
    // slide carry the motion; closing fades out all the way.
    // The island slides out from under the bar and widens as it comes; the
    // card scales up from just under it.
    opacity: root.island ? Math.min(1, root.progress * 5)
      : root.open ? 0.55 + 0.45 * Math.min(1, root.progress * 1.6) : root.progress
    scale: root.island ? 1 : 0.94 + 0.06 * root.progress
    transformOrigin: root.fromBottom ? Item.Bottom : Item.Top
    transform: Translate { y: root.island ? 0 : (root.fromBottom ? 1 : -1) * 12 * (1 - root.progress) }

    Behavior on height {
      enabled: root.open && root.progress >= 1 && root.animateHeight
      NumberAnimation { duration: root.heightDuration; easing.type: Easing.OutCubic }
    }
    Behavior on width {
      enabled: root.open && root.progress >= 1
      NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
    }

    // Glass: light catching the top edge, fading out a third of the way down.
    Rectangle {
      visible: !root.island
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.075) }
        GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.015) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
      }
    }

    // A brighter hairline along the top, like the lip of a glass pane.
    Rectangle {
      visible: !root.island
      x: parent.radius
      y: 1
      width: parent.width - parent.radius * 2
      height: 1
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.22) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
      }
    }

    // Laid out at the card's full size whatever the surface is doing, so the
    // island's morph reveals it (clipped) instead of reflowing it every frame.
    Item {
      id: contentHolder
      x: (surface.width - root.contentWidth) / 2 + root.padding
      y: root.fromBottom ? surface.height - root.contentHeight + root.padding : root.barPadding
      width: root.contentWidth - root.padding * 2
      height: root.contentHeight - root.padding - root.barPadding
      // The content trails the glass by a beat, so the card lands first.
      opacity: root.island ? root.islandContentT : root.open ? 1 : 0
      Behavior on opacity {
        enabled: !root.island
        SequentialAnimation {
          PauseAnimation { duration: root.open ? 40 : 0 }
          NumberAnimation { duration: root.open ? 220 : 110; easing.type: Easing.OutCubic }
        }
      }
      transformOrigin: root.fromBottom ? Item.Bottom : Item.Top
      scale: root.island ? 0.97 + 0.03 * root.islandContentT : 1
      transform: Translate {
        y: contentHolder.opacity < 1 ? (root.fromBottom ? 1 : -1) * (root.island ? 10 : 6) * (1 - contentHolder.opacity) : 0
      }
    }

    HoverHandler {
      id: cardHover
    }
  }

  Item {
    id: floatHolder
    anchors.fill: parent
    // Only while a float is up (not by floatMask.visible: that reads false while
    // this is hidden, so it could never come up): otherwise this full-window layer sits over
    // the card and its own hover handler keeps the card's controls from hovering.
    visible: !root.tucked && root.floatMask !== null
    opacity: surface.opacity

    // Only the mask's parts reach it, so this is the pointer on the float.
    HoverHandler {
      id: floatHover
    }
  }
}
