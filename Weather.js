.pragma library

// wttr.in's j1 report, boiled down for the Today pane. The glyphs are the
// bar's old weather widget's (Nerd Font), so the island matches what it replaced.

function iconForCode(code, night) {
  var c = parseInt(String(code || "0"), 10)
  switch (c) {
    case 113: return night ? "" : ""
    case 116: return night ? "" : ""
    case 119: case 122: return ""
    case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
    case 176: case 263: case 353: return night ? "" : ""
    case 179: case 227: case 230: case 323: case 326: case 368: return night ? "" : ""
    case 182: case 185: case 281: case 284: case 311: case 314:
    case 317: case 320: case 350: case 362: case 365: case 374: case 377: return ""
    case 200: case 386: case 389: case 392: case 395: return ""
    case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return ""
    case 329: case 332: case 335: case 338: case 371: return ""
    default: return ""
  }
}

var DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// Metric unless the locale says otherwise (en_US and a few others).
function imperial(locale) {
  var l = String(locale || "")
  return /^en[_-](US|LR)($|[_.-])/.test(l) || /^my($|[_.-])/.test(l)
}

function temp(c, f, imp) {
  var v = imp ? f : c
  return v === undefined || v === "" ? "" : v + "°"
}

// raw: the j1 JSON text; null when it isn't a usable report.
function parse(raw, imp, hour) {
  try {
    var r = JSON.parse(String(raw))
    var c = r.current_condition[0]
    var area = r.nearest_area && r.nearest_area[0]
    var days = []
    var list = r.weather || []
    // wttr's own country beats the locale: en_US in Rabat is still Celsius.
    var country = area && area.country && area.country[0] ? String(area.country[0].value) : ""
    if (country) imp = /^(united states|liberia|myanmar|burma)/i.test(country)
    for (var i = 0; i < list.length && days.length < 3; i++) {
      var d = list[i]
      var mid = (d.hourly || [])[4] || (d.hourly || [])[0] || {}
      days.push({
        name: i === 0 ? "Today" : DAYS[new Date(d.date + "T12:00:00").getDay()],
        hi: temp(d.maxtempC, d.maxtempF, imp),
        lo: temp(d.mintempC, d.mintempF, imp),
        icon: iconForCode(mid.weatherCode, false)
      })
    }
    return {
      temp: temp(c.temp_C, c.temp_F, imp),
      feels: temp(c.FeelsLikeC, c.FeelsLikeF, imp),
      desc: c.weatherDesc && c.weatherDesc[0] ? c.weatherDesc[0].value : "",
      icon: iconForCode(c.weatherCode, hour < 6 || hour >= 20),
      place: area && area.areaName && area.areaName[0] ? area.areaName[0].value : "",
      days: days
    }
  } catch (e) {
    return null
  }
}
