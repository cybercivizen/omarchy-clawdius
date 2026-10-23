.pragma library

// The month grid for the Today pane: always six Monday-first rows of seven,
// so stepping through the year never changes the card's height.

function pad2(n) { return (n < 10 ? "0" : "") + n }

function dateKey(year, month, day) {
  return year + "-" + pad2(month + 1) + "-" + pad2(day)
}

// ISO-8601 week number: the week owning that date's Thursday.
function isoWeek(year, month, day) {
  var date = new Date(Date.UTC(year, month, day))
  var weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 4 - weekday)
  var yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
  return Math.ceil(((date.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
}

// [{week, days: [{day, inMonth, weekend, today}]}]
function monthGrid(year, month, todayKey) {
  var leading = (new Date(year, month, 1).getDay() + 6) % 7
  var cursor = new Date(year, month, 1 - leading)
  var weeks = []
  for (var w = 0; w < 6; w++) {
    var days = []
    var monday = null
    for (var d = 0; d < 7; d++) {
      var y = cursor.getFullYear(), m = cursor.getMonth(), n = cursor.getDate()
      if (d === 0) monday = { y: y, m: m, n: n }
      days.push({
        day: n,
        inMonth: m === month && y === year,
        weekend: d >= 5,
        today: dateKey(y, m, n) === todayKey
      })
      cursor.setDate(n + 1)
    }
    weeks.push({ week: isoWeek(monday.y, monday.m, monday.n), days: days })
  }
  return weeks
}

function stepMonth(year, month, delta) {
  var t = new Date(year, month + delta, 1)
  return { year: t.getFullYear(), month: t.getMonth() }
}

var months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
