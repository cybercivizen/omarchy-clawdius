import QtQuick
import qs.Commons

// The crab's colors, worked out from the theme's ink (fg) and paper (bg), so
// light and dark themes both read. On a monochrome desktop orange means
// "Claude is doing something"; anything idle is gray, amber needs you, and
// green / red are done / failed.
QtObject {
  id: root

  property color fg: Color.foreground
  property color bg: Color.background
  // The `color` setting: replaces the crab orange in both themes; "" is auto.
  property string crabOverride: ""
  // The bar's own color: the island takes it exactly, so the two are one
  // surface. Transparent (a theme preview) falls back to the mix below.
  property color barColor: "transparent"

  function luminance(c) {
    function ch(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b)
  }
  function mix(a, b, t) {
    a = Qt.color(a); b = Qt.color(b)
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }
  function alpha(c, a) { c = Qt.color(c); return Qt.rgba(c.r, c.g, c.b, a) }
  // Black or white text on a filled color, whichever reads.
  function onFill(c) { return luminance(Qt.color(c)) > 0.4 ? "#101315" : "#ffffff" }

  // Dark ink means a light theme.
  readonly property bool light: luminance(fg) < 0.5

  // Text: strong for names and headlines, muted for captions, dim for done steps.
  // (Mixed toward the paper, not Qt.darker, which only darkens dark ink further.)
  readonly property color strong: light ? mix(fg, "#000000", 0.5) : mix(fg, "#ffffff", 0.75)
  readonly property color muted: mix(fg, bg, 0.35)
  readonly property color dim: mix(fg, bg, 0.5)

  // #D97757 is under 3:1 on white; #C15F3C is about 4:1.
  readonly property color crab: crabOverride !== "" ? crabOverride : light ? "#C15F3C" : "#D97757"
  readonly property color idleCrab: muted
  readonly property color needsYou: light ? "#B7791F" : "#E8A317"
  readonly property color needsYouText: light ? "#9A6700" : "#F0B545"
  readonly property color done: light ? "#1A7F37" : "#2DA44E"
  readonly property color failed: light ? "#CF222E" : "#D1242F"
  // Out of usage: a session stopped by the limit, not by anything it did.
  readonly property color limit: light ? "#8250DF" : "#A371F7"
  // The posture nudge: calm, not a session's status.
  readonly property color posture: light ? "#0E7C86" : "#3CBFC0"
  // Effort, cool to hot as it climbs: low … max; the default stays muted.
  // Pastel: each hue softened toward the page so the levels don't shout.
  function effort(e) {
    var c = e === "low" ? "#7FC8C8" : e === "medium" ? "#9FD3A8" : e === "high" ? "#EBCB8B"
      : e === "xhigh" ? "#F0A98C" : e === "max" ? "#E89AA0" : ""
    return c === "" ? muted : light ? mix(c, fg, 0.35) : c
  }

  // The island: near-black (Solitude's darker background) holding cards one
  // step lighter; the peek and menus sit one step above those.
  readonly property color island: barColor.a > 0 ? alpha(barColor, 1)
    : light ? mix(bg, fg, 0.05) : mix(bg, "#000000", 0.45)
  readonly property color card: light ? bg : mix(bg, fg, 0.02)
  readonly property color raised: light ? bg : mix(bg, fg, 0.06)
  readonly property color well: light ? mix(bg, fg, 0.04) : mix(bg, "#000000", 0.3)
  readonly property color hairline: alpha(fg, 0.07)
  readonly property color line: alpha(fg, 0.12)

  // Pills: the main action filled with ink, the rest a faint wash.
  readonly property color primary: light ? fg : mix(fg, "#ffffff", 0.6)
  readonly property color primaryInk: bg
  readonly property color secondary: alpha(fg, 0.10)
}
