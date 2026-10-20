import QtQuick
import "Sprite.js" as Sprite

// The crab, painted as hard-edged rectangles so it stays pixel art at any
// scale. `mood` picks the pose loop (see Sprite.MOODS); it blinks every few
// seconds unless the pose holds its eyes, and `sweat` runs a drop down its
// side.
Item {
  id: root

  property real unit: 2
  property color color: "#D97757"
  property color sweatColor: "#7FB8FF"
  property string mood: "idle"
  property bool sweat: false
  property bool animate: true
  property int typingInterval: 150

  readonly property bool working: mood === "typing"
  readonly property int tempo: mood === "typing" ? typingInterval : (Sprite.TEMPO[mood] || 0)

  property int step: 0
  property bool blink: false
  property int sweatStep: 0

  readonly property var pixels: Sprite.frame(mood, step, blink, sweat && sweatStep < 4 ? sweatStep : -1)
  // Whole pixels per grid unit: a fractional one rounds the two eyes to
  // different widths.
  readonly property real px: unit >= 1 ? Math.round(unit) : unit

  implicitWidth: Sprite.W * px
  implicitHeight: Sprite.H * px

  onMoodChanged: step = 0

  // Thoughts: while it listens, pixel glyphs drift up off its head, swaying,
  // and fade out: a chunky "?", a twinkle, a little "?". One clock drives
  // three of them a third of a cycle apart; each takes its next glyph and
  // lane while it's out of sight, so they never pop, and the three in the
  // air are always different. Up to 5 x 7 cells; `size` is a cell in grid
  // units.
  property bool thoughts: mood === "listening"
  readonly property var glyphs: [
    { size: 0.8, rows: [".###.", "##.##", "...##", "..##.", "..##.", ".....", "..##."] },
    { size: 0.6, rows: [".#.", "###", ".#."] },
    { size: 0.6, rows: ["###", "..#", ".##", "...", ".#."] }
  ]
  // Grid columns their paths are centred on, taken in turn: one after the
  // other lands well apart.
  readonly property var lanes: [13.5, 4.5, 10, 6]
  // Comes and goes with a fade, not all at once.
  property real thoughtsShown: thoughts ? 1 : 0
  Behavior on thoughtsShown { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
  // Each glyph's life is a cycle, 0..1. Four to a loop (twelve glyphs), so
  // the loop wraps without changing any glyph or lane mid-flight.
  property real flow: 0
  NumberAnimation on flow {
    from: 0
    to: 4
    duration: 4 * 2900
    loops: Animation.Infinite
    running: root.thoughtsShown > 0 && root.animate && root.visible
  }

  function smoothstep(v) { v = Math.max(0, Math.min(1, v)); return v * v * (3 - 2 * v) }

  component Thought: Item {
    id: thought
    property int slot: 0
    readonly property real phase: root.flow + slot / 3
    readonly property real t: phase - Math.floor(phase)
    // Which glyph this is, counting from the loop's start: slot 2 goes up
    // first, then 1, then 0.
    readonly property int nth: 3 * Math.floor(phase) - slot + 2
    readonly property var glyph: root.glyphs[nth % root.glyphs.length]
    readonly property real lane: root.lanes[nth % root.lanes.length]
    // Whole pixels, so every cell of a glyph comes out the same size.
    readonly property real cell: Math.max(1, Math.round(root.px * glyph.size))

    width: glyph.rows[0].length * cell
    height: glyph.rows.length * cell
    // In over the first fifth, out over the back half.
    opacity: root.thoughtsShown * root.smoothstep(t / 0.2) * (1 - root.smoothstep((t - 0.5) / 0.5))
    visible: opacity > 0.01
    // Rises fast off the head and slows as it fades, swaying under a grid
    // unit either side; whole pixels, so the edges stay crisp.
    x: Math.round(lane * root.px + Math.sin((t * 1.5 + slot / 3) * Math.PI * 2) * 0.7 * root.px - width / 2)
    y: Math.round(-root.px - height - (1 - (1 - t) * (1 - t)) * 9 * root.px)

    Repeater {
      model: 35
      Rectangle {
        required property int index
        readonly property int col: index % 5
        readonly property int row: Math.floor(index / 5)
        visible: row < thought.glyph.rows.length && thought.glyph.rows[row].charAt(col) === "#"
        x: col * thought.cell
        y: row * thought.cell
        width: thought.cell
        height: thought.cell
        color: root.color
        antialiasing: false
      }
    }
  }

  Thought { slot: 0 }
  Thought { slot: 1 }
  Thought { slot: 2 }

  // A fixed set of rectangles, each taking its piece of the current frame
  // (a pose has at most 14): handing the Repeater each frame's new array
  // would destroy and rebuild them all, several times a second per crab.
  Repeater {
    model: 16

    Rectangle {
      required property int index
      readonly property var modelData: root.pixels[index] || ({ x: 0, y: 0, w: 0, h: 0, tint: "" })
      visible: index < root.pixels.length
      x: Math.round(modelData.x * root.px)
      y: Math.round(modelData.y * root.px)
      width: Math.round((modelData.x + modelData.w) * root.px) - x
      height: Math.round((modelData.y + modelData.h) * root.px) - y
      color: modelData.tint === "sweat" ? root.sweatColor : root.color
      antialiasing: false
    }
  }

  Timer {
    running: root.tempo > 0 && root.animate && root.visible
    interval: Math.max(40, root.tempo)
    repeat: true
    onTriggered: root.step = (root.step + 1) % Sprite.steps(root.mood)
    onRunningChanged: if (!running) root.step = 0
  }

  Timer {
    // The drop runs down, then a beat before the next one.
    running: root.sweat && root.animate && root.visible
    interval: 220
    repeat: true
    onTriggered: root.sweatStep = (root.sweatStep + 1) % 7
  }

  Timer {
    id: blinkTimer
    running: root.animate && root.visible && root.mood !== "sleep" && root.mood !== "failed"
    interval: 2600 + Math.random() * 2600
    repeat: true
    onTriggered: {
      root.blink = true
      blinkOff.restart()
      interval = 2600 + Math.random() * 2600
    }
  }

  Timer {
    id: blinkOff
    interval: 130
    onTriggered: root.blink = false
  }
}
