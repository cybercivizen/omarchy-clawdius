.pragma library

// Timers, alarms, reminders and the posture check: the sums and the words.
// A timer is {id, kind: timer | alarm | remind, label, at (ms), len (ms)}.

var kinds = [
  { id: "timer", name: "Timer", verb: "Start", ring: "Timer" },
  { id: "alarm", name: "Alarm", verb: "Set alarm", ring: "Alarm" },
  { id: "remind", name: "Remind", verb: "Remind me", ring: "Reminder" }
]

var presets = [5, 10, 25, 45]
var intervals = [20, 30, 45, 60]
var reminders = ["Stretch", "Drink water", "Rest your eyes", "Stand up", "Check the build"]

// What the crab says when it's time to sit up, and how often it's heard.
var postureLines = [
  "Sit tall, crab-friend.",
  "Shoulders down, claws loose.",
  "Unclench your jaw. Roll your neck.",
  "Feet flat. Crabs walk sideways, you shouldn't sit that way.",
  "Screen at eye level, chin back.",
  "Stand up and shake out the claws.",
  "Look at something far away for 20 seconds."
]

function postureLine(n) {
  return postureLines[Math.abs(n) % postureLines.length]
}

function pad(n) {
  return (n < 10 ? "0" : "") + n
}

// Time left on a running thing: 4:32 under an hour, 1h 05m above.
function left(ms) {
  var s = Math.max(0, Math.ceil(ms / 1000))
  var h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60
  if (h > 0) return h + "h " + pad(m) + "m"
  return m + ":" + pad(s % 60)
}

// The value shown on the setter: minutes as "10 min" / "1h 30m".
function span(min) {
  if (min < 60) return min + " min"
  return Math.floor(min / 60) + "h" + (min % 60 ? " " + pad(min % 60) + "m" : "")
}

function clock(minOfDay) {
  var m = ((minOfDay % 1440) + 1440) % 1440
  return pad(Math.floor(m / 60)) + ":" + pad(m % 60)
}

// The next time the clock reads minOfDay, strictly after `now`.
function nextClock(minOfDay, now) {
  var d = new Date(now)
  d.setHours(Math.floor(minOfDay / 60), minOfDay % 60, 0, 0)
  if (d.getTime() <= now) d.setDate(d.getDate() + 1)
  return d.getTime()
}

// A sensible alarm to start from: the next half hour.
function defaultAlarm(now) {
  var d = new Date(now + 30 * 60000)
  return d.getHours() * 60 + (d.getMinutes() < 30 ? 0 : 30)
}

// Steps for the − / + buttons: finer when short.
function step(min, dir) {
  var by = min < 10 || (min === 10 && dir < 0) ? 1 : min < 60 || (min === 60 && dir < 0) ? 5 : 15
  return Math.max(1, Math.min(600, min + dir * by))
}

function id() {
  return Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
}

function ringName(kind) {
  for (var i = 0; i < kinds.length; i++) if (kinds[i].id === kind) return kinds[i].ring
  return "Timer"
}
