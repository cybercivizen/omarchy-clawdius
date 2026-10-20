import QtQuick
import qs.Commons

// The key window's field (KeyWindow.qml), drawn in the card: its text,
// selection and caret. The field is laid out at this width in the same font,
// so positions carry over both ways: a click puts the caret there, a drag
// selects, a double-click takes the word, as LiveTerm's composer does.
Item {
  id: root

  property QtObject pal
  property var field: null
  property bool focused: true
  property int fontSize: Style.font.subtitle
  property string fontFamily: Style.font.family
  property string placeholder: ""
  property bool wrap: true
  property color ink: pal ? pal.fg : "white"
  property color hot: pal ? pal.crab : "#D97757"

  // A click on it: the key window should take the keyboard back.
  signal focusRequested()

  readonly property string text: field ? field.text : ""

  implicitHeight: shown.implicitHeight
  clip: !wrap

  TextEdit {
    id: shown
    width: parent.width
    text: root.text
    textFormat: TextEdit.PlainText
    wrapMode: root.wrap ? TextEdit.Wrap : TextEdit.NoWrap
    readOnly: true
    activeFocusOnPress: false
    selectByMouse: false
    cursorVisible: false
    color: root.ink
    selectionColor: root.pal ? root.pal.alpha(root.hot, 0.4) : "#66D97757"
    selectedTextColor: root.ink
    font.family: "monospace"
    font.pixelSize: root.fontSize
    onTextChanged: { mirrorSelection(); placeCaret() }
    Component.onCompleted: placeCaret()
    onWidthChanged: placeCaret()
    onContentWidthChanged: placeCaret()
    onContentHeightChanged: placeCaret()
    function mirrorSelection() {
      if (root.field) shown.select(root.field.selectionStart, root.field.selectionEnd)
    }
    // The caret goes where this drawing puts the field's cursor, not where
    // the field's own layout does: that one is only as right as its width
    // and size are, and a stale one left the caret back among the letters.
    property rect caretRect: Qt.rect(0, 0, 0, font.pixelSize)
    // Once the text is laid out: asked mid-change, it answers for the old one.
    function placeCaret() { Qt.callLater(shown.measureCaret) }
    function measureCaret() {
      if (root.field) caretRect = shown.positionToRectangle(Math.min(root.field.cursorPosition, length))
    }
  }

  Connections {
    target: root.field
    function onSelectionStartChanged() { shown.mirrorSelection() }
    function onSelectionEndChanged() { shown.mirrorSelection() }
    function onCursorPositionChanged() { shown.placeCaret() }
  }

  Text {
    visible: root.text === ""
    x: caret.width + Style.space(4)
    width: parent.width - x
    anchors.verticalCenter: shown.verticalCenter
    text: root.placeholder
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: root.pal ? root.pal.muted : "gray"
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  Rectangle {
    id: caret
    visible: root.focused
    x: shown.caretRect.x
    y: shown.caretRect.y
    width: Math.max(2, Style.spaceReal(2))
    height: shown.caretRect.height
    radius: width / 2
    color: root.hot
    SequentialAnimation on opacity {
      running: caret.visible
      loops: Animation.Infinite
      NumberAnimation { to: 1; duration: 0 }
      PauseAnimation { duration: 530 }
      NumberAnimation { to: 0; duration: 0 }
      PauseAnimation { duration: 530 }
    }
  }

  MouseArea {
    anchors.fill: parent
    anchors.margins: -Style.space(4)
    cursorShape: Qt.IBeamCursor
    property int anchorAt: 0
    function at(mouse) { return shown.positionAt(mouse.x - Style.space(4), mouse.y - Style.space(4)) }
    onPressed: function(mouse) {
      root.focusRequested()
      if (!root.field) return
      anchorAt = at(mouse)
      root.field.cursorPosition = anchorAt
    }
    onPositionChanged: function(mouse) {
      if (pressed && root.field) root.field.select(anchorAt, at(mouse))
    }
    onDoubleClicked: function(mouse) {
      if (!root.field) return
      root.field.cursorPosition = at(mouse)
      root.field.selectWord()
    }
  }
}
