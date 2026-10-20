.pragma library

// Small text helpers the island's views share.

// A running turn's elapsed time, to the second: 12s, 4m 12s, 1h 04m.
function clock(now, startMs) {
  if (!startMs) return ""
  var s = Math.max(0, Math.floor((now - startMs) / 1000))
  if (s < 60) return s + "s"
  var m = Math.floor(s / 60)
  if (m < 60) return m + "m " + (s % 60 < 10 ? "0" : "") + (s % 60) + "s"
  return Math.floor(m / 60) + "h " + (m % 60 < 10 ? "0" : "") + (m % 60) + "m"
}

// Seconds as a duration: 48s, 2m 14s, 1h 5m.
function seconds(sec) {
  sec = Math.max(0, Math.round(sec || 0))
  if (sec < 60) return sec + "s"
  var m = Math.floor(sec / 60)
  if (m < 60) return m + "m " + (sec % 60) + "s"
  return Math.floor(m / 60) + "h " + (m % 60) + "m"
}

// How long ago a millisecond time was: 40s, 12m, 3h, 2d.
function ago(now, ms) {
  if (!ms) return ""
  var s = Math.max(0, Math.round((now - ms) / 1000))
  if (s < 60) return s + "s"
  var m = Math.round(s / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  if (h < 24) return h + "h"
  return Math.floor(h / 24) + "d"
}

function tokens(n, unit) {
  n = Number(n) || 0
  unit = unit === undefined ? " tokens" : unit
  if (n < 1000) return n + unit
  if (n < 10000) return (n / 1000).toFixed(1) + "k" + unit
  return Math.round(n / 1000) + "k" + unit
}

function folder(cwd, home) {
  cwd = String(cwd || "")
  if (home && cwd === home) return "~"
  return home && cwd.indexOf(home + "/") === 0 ? "~/" + cwd.slice(home.length + 1) : cwd
}
