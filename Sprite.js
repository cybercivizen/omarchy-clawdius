.pragma library

// Clawd, the Claude Code crab, decoded from the CLI's quadrant-block art
//
//    ▐▛███▜▌
//   ▝▜█████▛▘
//     ▘▘ ▝▝
//
// onto a square 18 x 10 grid (each block quadrant is twice as tall as it is
// wide, so every art row becomes two grid rows). Rectangles are {x, y, w, h}
// in grid units, plus an optional `tint` ("sweat") the caller colors; the
// caller scales and paints them.

var W = 18
var H = 10

// pose.armL / pose.armR: vertical offset of each claw in grid units
//   (+1 = pressing a key, negative = raised; -3 is level with the eyes).
// pose.eyes: "open", "shut" (a slit: blinking, asleep, deflated) or "up"
//   (looking up, mid-thought).
// pose.sweat: -1 for none, else how far the drop has run down the side (0..3).
function rects(pose) {
  var r = []
  function add(x, y, w, h, tint) { r.push({ x: x, y: y, w: w, h: h, tint: tint || "" }) }

  add(3, 0, 12, 2)                       // top of the shell
  add(3, 2, 2, 2); add(6, 2, 6, 2); add(13, 2, 2, 2)  // eye row; gaps at 5 and 12 are the eyes
  if (pose.eyes === "shut") { add(5, 2, 1, 1); add(12, 2, 1, 1) }
  else if (pose.eyes === "up") { add(5, 3, 1, 1); add(12, 3, 1, 1) }
  add(3, 4, 12, 4)                       // body
  add(1, 4 + (pose.armL || 0), 2, 2)     // claws
  add(15, 4 + (pose.armR || 0), 2, 2)
  add(4, 8, 1, 2); add(6, 8, 1, 2); add(11, 8, 1, 2); add(13, 8, 1, 2)  // legs
  if (pose.sweat >= 0) add(16, Math.min(3, pose.sweat), 1, 1, "sweat")
  return r
}

// Each mood is a short loop of poses; Clawd.qml steps through it.
//   typing     left claw taps, both up, right claw taps, both up
//   thinking   a claw at the chin, eyes up; it taps now and then
//   waiting    the right claw waves you over
//   done       both claws up and down: celebrating
//   failed     claws down, eyes half shut
//   sleep      eyes shut, claws resting
//   listening  eyes up, then back: waiting on you to say something (chat)
//   searching  claws sweep up one after the other: looking around (search)
//   found      the right claw points, then dips: this one (search)
var MOODS = {
  idle:     [{}],
  typing:   [{ armL: 1 }, {}, { armR: 1 }, {}],
  thinking: [{ armR: -1, eyes: "up" }, { armR: -1, eyes: "up" }, { armR: -1, eyes: "up" }, { armR: -2, eyes: "up" }],
  waiting:  [{ armR: -3 }, { armR: -1 }],
  done:     [{ armL: -3, armR: -3 }, { armL: -1, armR: -1 }],
  failed:   [{ armL: 2, armR: 2, eyes: "shut" }],
  sleep:    [{ eyes: "shut" }],
  listening: [{ eyes: "up" }, { eyes: "up" }, {}, {}],
  searching: [{ armR: -2 }, { armR: -2, armL: -1 }, { armL: -2 }, { armR: -1, armL: -2 }],
  found:    [{ armR: -3 }, { armR: -3 }, { armR: -2 }]
}

// Milliseconds per pose, for moods that move.
var TEMPO = { typing: 150, thinking: 700, waiting: 240, done: 180, listening: 900, searching: 420, found: 360 }

function steps(mood) { return (MOODS[mood] || MOODS.idle).length }

function frame(mood, step, blink, sweat) {
  var loop = MOODS[mood] || MOODS.idle
  var p = loop[step % loop.length]
  var eyes = p.eyes || (blink ? "shut" : "open")
  return rects({ armL: p.armL || 0, armR: p.armR || 0, eyes: eyes, sweat: sweat })
}
