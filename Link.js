.pragma library

// The bar only lets a plugin look up its own widgets, so the clock cannot
// find the crab through it. This library script is shared by everything in
// the shell that imports it, which makes it the meeting point: crabs
// register here, and the clock (through ClockLink.qml) reports its hover.

var crabs = []

function register(crab) {
  if (crabs.indexOf(crab) < 0) crabs.push(crab)
}

function unregister(crab) {
  var i = crabs.indexOf(crab)
  if (i >= 0) crabs.splice(i, 1)
}

// Hover goes to the crab on the same bar window: one bar per monitor.
function clockHover(window, hovered) {
  for (var i = crabs.length - 1; i >= 0; i--) {
    var crab = crabs[i]
    try {
      if (crab && crab.barWindow === window) crab.setClockHover(hovered)
    } catch (e) {
      crabs.splice(i, 1)   // destroyed by a reload
    }
  }
}

// A click on the clock: the island on Today, on that bar's crab.
function clockClick(window) {
  for (var i = crabs.length - 1; i >= 0; i--) {
    var crab = crabs[i]
    try {
      if (crab && crab.barWindow === window && crab.drawn()) { crab.clockClick(); return }
    } catch (e) {
      crabs.splice(i, 1)
    }
  }
}

// Every crab sees each permission prompt, but only one card should drop open:
// a drawn crab (not the bar's zero-size placeholder) on the focused monitor,
// the same rule the bar uses to route a panel hotkey.
function approvalCrab(focusedScreen) {
  var pool = []
  for (var i = crabs.length - 1; i >= 0; i--) {
    try {
      if (crabs[i].drawn()) pool.push(crabs[i])
    } catch (e) {
      crabs.splice(i, 1)
    }
  }
  for (var j = 0; j < pool.length; j++)
    if (pool[j].screenName() === focusedScreen) return pool[j]
  return pool.length ? pool[0] : null
}

// Each crab's own state, for the debug call (only one crab answers IPC).
function states() {
  var out = []
  for (var i = 0; i < crabs.length; i++) {
    try { out.push(crabs[i].state()) } catch (e) {}
  }
  return out
}

// The crab whose island is up, if any.
function openCrab() {
  for (var i = 0; i < crabs.length; i++) {
    try { if (crabs[i].opened) return crabs[i] } catch (e) {}
  }
  return null
}

// Every crab's island shut (IPC close: only one crab answers IPC).
function closeAll() {
  for (var i = 0; i < crabs.length; i++) {
    try { crabs[i].close() } catch (e) {}
  }
}

// The one crab that keeps shared state on disk (app usage), so the copies on
// other monitors don't write over each other.
function isLeader(crab) {
  // A crab destroyed by a reload can linger at the front; drop it or nobody leads.
  while (crabs.length > 0) {
    try { crabs[0].stateDir; break } catch (e) { crabs.shift() }
  }
  return crabs.length > 0 && crabs[0] === crab
}

function count() {
  return crabs.length
}
