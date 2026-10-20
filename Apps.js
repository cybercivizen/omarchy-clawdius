.pragma library

// The search view's app matching: installed desktop entries ranked against
// what's typed, nudged by how recently and how often each was used (the
// usage record BarWidget keeps: id → {n: times used, t: last ms}).

function visible(entries) {
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e && !e.noDisplay && e.name) out.push(e)
  }
  return out
}

function keywords(entry) {
  try { return entry.keywords && entry.keywords.join ? entry.keywords.join(" ") : "" } catch (e) { return "" }
}

function words(text) {
  return String(text || "").replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase().split(/[^a-z0-9]+/).filter(function(w) { return w })
}

// 0 for no match; higher is better.
function match(entry, query) {
  var q = query.toLowerCase()
  var name = String(entry.name || "").toLowerCase()
  if (name === q) return 120
  if (name.indexOf(q) === 0) return 100
  var nameWords = words(entry.name)
  for (var i = 0; i < nameWords.length; i++)
    if (nameWords[i].indexOf(q) === 0) return 85
  if (name.indexOf(q) >= 0) return 70
  var acronym = nameWords.map(function(w) { return w.charAt(0) }).join("")
  if (q.length >= 2 && acronym.indexOf(q) === 0) return 60
  var rest = [entry.genericName, keywords(entry), entry.id, entry.comment].join(" ").toLowerCase()
  if (words(rest).some(function(w) { return w.indexOf(q) === 0 })) return 45
  if (rest.indexOf(q) >= 0) return 30
  return 0
}

// Used recently and often counts for more, but never outranks a better match.
function boost(usage, entry, now) {
  var u = usage && usage[entry.id]
  if (!u) return 0
  var days = Math.max(0, (now - (u.t || 0)) / 86400000)
  return Math.min(10, Math.log(1 + (u.n || 0)) * 2) + Math.max(0, 8 - days)
}

function search(entries, query, usage, now, limit) {
  var all = visible(entries)
  var terms = String(query || "").trim().split(/\s+/).filter(function(t) { return t })
  var scored = []
  for (var i = 0; i < all.length; i++) {
    var total = 0
    for (var j = 0; j < terms.length; j++) {
      var m = match(all[i], terms[j])
      if (!m) { total = 0; break }
      total += m
    }
    if (total) scored.push({ entry: all[i], score: total + boost(usage, all[i], now) })
  }
  scored.sort(function(a, b) { return b.score - a.score || String(a.entry.name).localeCompare(String(b.entry.name)) })
  return scored.slice(0, limit).map(function(s) { return s.entry })
}

// The row shown before anything is typed: the most used lately, then
// whatever is open now, then a few everyday ones so it's never empty.
function suggested(entries, usage, openIds, now, limit) {
  var all = visible(entries)
  var byId = {}
  for (var i = 0; i < all.length; i++) byId[all[i].id] = all[i]
  var ranked = Object.keys(usage || {}).filter(function(id) { return byId[id] })
  ranked.sort(function(a, b) { return boost(usage, byId[b], now) - boost(usage, byId[a], now) })
  var out = []
  function add(id) { if (byId[id] && out.indexOf(byId[id]) < 0 && out.length < limit) out.push(byId[id]) }
  ranked.forEach(add)
  ;(openIds || []).forEach(add)
  var everyday = /^(web browser|terminal|terminal emulator|file manager|text editor)$/i
  var kinds = {}
  for (var k = 0; k < all.length && out.length < limit; k++) {
    var kind = String(all[k].genericName || "").trim().toLowerCase()
    if (everyday.test(kind) && !kinds[kind]) { kinds[kind] = true; add(all[k].id) }
  }
  return out
}
