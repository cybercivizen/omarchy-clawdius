.pragma library

// The search view's sums: what's typed, read as arithmetic, or null when it
// isn't any. A small parser of its own, nothing is eval'd. + - * / % ^ (and
// ** × ÷ −), brackets, 2(3) and 2pi for times, pi and e, and a few
// functions: sqrt abs round floor ceil ln log sin cos tan. A bare number or
// name isn't a sum (typing "e" looks for an app), nor is an unfinished one.

var functions = {
  sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
  ln: Math.log, log: function(x) { return Math.log(x) / Math.LN10 },
  sin: Math.sin, cos: Math.cos, tan: Math.tan
}
var constants = { pi: Math.PI, e: Math.E }

function tokens(text) {
  var src = String(text || "").replace(/[×·]/g, "*").replace(/÷/g, "/").replace(/[−–]/g, "-").replace(/\*\*/g, "^")
  var out = []
  var re = /^\s*(?:(\d+(?:\.\d*)?|\.\d+)|([a-z]+)|([-+*\/%^()]))/
  src = src.trim().toLowerCase()
  while (src.length) {
    var m = re.exec(src)
    if (!m) return null
    src = src.slice(m[0].length)
    if (m[1] !== undefined) out.push({ num: parseFloat(m[1]) })
    else if (m[2] !== undefined) out.push({ name: m[2] })
    else out.push({ op: m[3] })
  }
  return out
}

function evaluate(text) {
  var list = tokens(text)
  if (!list || !list.length) return null
  var i = 0
  var worked = false

  function peek(op) { return list[i] && list[i].op === op }

  // expr: terms joined by + -
  function expr() {
    var v = term()
    while (peek("+") || peek("-")) {
      var op = list[i++].op
      var r = term()
      v = op === "+" ? v + r : v - r
      worked = true
    }
    return v
  }

  // term: powers joined by * / %, or side by side: 2(3), 2pi, 3 sqrt(4)
  function term() {
    var v = unary()
    for (;;) {
      if (peek("*") || peek("/") || peek("%")) {
        var op = list[i++].op
        var r = unary()
        v = op === "*" ? v * r : op === "/" ? v / r : v % r
        worked = true
      } else if (list[i] && (list[i].name !== undefined || peek("("))) {
        v = v * unary()
        worked = true
      } else return v
    }
  }

  function unary() {
    if (peek("-")) { i++; return -unary() }
    if (peek("+")) { i++; return unary() }
    return power()
  }

  // power: right to left, and above a leading minus: -2^2 is -4
  function power() {
    var v = atom()
    if (peek("^")) { i++; worked = true; return Math.pow(v, unary()) }
    return v
  }

  function atom() {
    var t = list[i++]
    if (!t) throw "end"
    if (t.num !== undefined) return t.num
    if (t.op === "(") {
      var v = expr()
      // An unclosed bracket at the very end is fine: "(2+3" reads as typed so far.
      if (peek(")")) i++
      else if (i < list.length) throw "bracket"
      return v
    }
    if (t.name !== undefined) {
      if (functions.hasOwnProperty(t.name)) {
        worked = true
        return functions[t.name](power())
      }
      if (constants.hasOwnProperty(t.name)) return constants[t.name]
    }
    throw "token"
  }

  try {
    var value = expr()
    if (i < list.length || !worked || !isFinite(value)) return null
    // 0.1 + 0.2 is 0.3: twelve significant digits hide the float noise.
    value = parseFloat(value.toPrecision(12))
    return { value: value, text: String(value) }
  } catch (e) {
    return null
  }
}
