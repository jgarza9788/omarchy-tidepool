// Pure helpers for the Tidepool bar widget. ES5-only so `node tests/model.test.js`
// runs it. Nothing here reads the clock; callers pass `now` (a Date or ms).

var DAY_MS = 24 * 60 * 60 * 1000

// Material Design icon code points (Nerd Font v3).
var GLYPH = {
  calendar: 0xF00ED, "calendar-plus": 0xF00F3, timer: 0xF051B, media: 0xF0386, play: 0xF040A, pause: 0xF03E4, next: 0xF04AD, prev: 0xF04AE,
  left: 0xF0141, right: 0xF0142, close: 0xF0156, plus: 0xF0415, trash: 0xF01B4, refresh: 0xF0450, cog: 0xF0493,
  globe: 0xF01E7, check: 0xF012C, alert: 0xF0026, thermo: 0xF050F, wind: 0xF059D, pin: 0xF0403,
  clock: 0xF0150, palette: 0xF03D8,
  video: 0xF0567, open: 0xF03CC, mail: 0xF01EE, account: 0xF0004, shuffle: 0xF049D, repeat: 0xF0456, "repeat-once": 0xF0458, volume: 0xF057E, "volume-off": 0xF0581,
  sun: 0xF0599, moon: 0xF0594, "partly-day": 0xF0595, "partly-night": 0xF0F31, cloud: 0xF0590, fog: 0xF0591,
  drizzle: 0xF0597, rain: 0xF0596, snow: 0xF0598, storm: 0xF0593
}
function glyph(name) { return GLYPH[name] ? String.fromCodePoint(GLYPH[name]) : "" }

// ── Settings ────────────────────────────────────────────────────────────────
var VIZ_STYLES = ["bars", "mirror", "dots", "wave", "line", "fire"]
var VIZ_LABELS = { bars: "Bars", mirror: "Mirror", dots: "Dots", wave: "Wave", line: "Line", fire: "Fire" }
// The name shown for a style, and the style `delta` steps away (wraps round).
function vizLabel(style) { return VIZ_LABELS[style] || VIZ_LABELS.bars }
function vizStep(style, delta) {
  var at = VIZ_STYLES.indexOf(style)
  if (at < 0) at = 0
  var n = VIZ_STYLES.length
  return VIZ_STYLES[(((at + delta) % n) + n) % n]
}
var EXTRA_STYLES = ["plain", "border", "button"]
var CLOCK_MODES = ["time", "date", "both"]
var DEFAULTS = {
  clockMode: "time", showEvent: true, showTimer: true, showMedia: false, showWeather: false, extrasShown: 4, extraStyle: "plain", showMediaStatus: false, miniVisualizer: false, visualizerStyle: "bars",
  format: "HH:mm", dateFormat: "ddd d MMM", peekOnHover: true,
  rotateSeconds: 6, soonMinutes: 15, notifyMinutes: 5, chipMaxChars: 22, chipHorizonHours: 12, tideLine: true, weatherCity: "", weatherLat: null, weatherLon: null, units: "metric",
  worldClocks: "", timerPresets: "5,15,25,45", weekStart: "monday"
}

function clamp(v, lo, hi, fallback) {
  var n = Number(v)
  if (!isFinite(n)) return fallback
  return Math.max(lo, Math.min(hi, Math.round(n)))
}

function resolveSettings(raw) {
  var s = raw || {}
  // Older entries chose a whole "face"; map it onto the toggles.
  if (s.face !== undefined && s.clockMode === undefined) {
    var legacy = {}
    for (var key in s) legacy[key] = s[key]
    var fill = function (k, v) { if (legacy[k] === undefined) legacy[k] = v }
    if (s.face === "clock") { fill("showEvent", false); fill("showTimer", false) }
    else if (s.face === "rotate") { fill("extrasShown", 1); fill("showMedia", true) }
    s = legacy
  }
  // The old name for the media extra's switch.
  if (s.showMedia === undefined && s.showMusic !== undefined) {
    var renamed = {}
    for (var k3 in s) renamed[k3] = s[k3]
    renamed.showMedia = s.showMusic
    s = renamed
  }
  // The old rotate switch: on meant one at a time, off meant all together.
  if (s.extrasShown === undefined && s.rotateExtras !== undefined) {
    var shim = {}
    for (var k2 in s) shim[k2] = s[k2]
    shim.extrasShown = s.rotateExtras === true || s.rotateExtras === "true" ? 1 : 4
    s = shim
  }
  var out = {}
  for (var k in DEFAULTS) out[k] = s[k] !== undefined && s[k] !== null ? s[k] : DEFAULTS[k]
  if (CLOCK_MODES.indexOf(out.clockMode) < 0) out.clockMode = DEFAULTS.clockMode
  var flags = ["showEvent", "showTimer", "showMedia", "showWeather"]
  for (var f = 0; f < flags.length; ++f) out[flags[f]] = out[flags[f]] !== false && out[flags[f]] !== "false"
  out.peekOnHover = out.peekOnHover !== false && out.peekOnHover !== "false"
  out.showMediaStatus = out.showMediaStatus === true || out.showMediaStatus === "true"
  out.miniVisualizer = out.miniVisualizer === true || out.miniVisualizer === "true"
  if (VIZ_STYLES.indexOf(out.visualizerStyle) < 0) out.visualizerStyle = DEFAULTS.visualizerStyle
  if (EXTRA_STYLES.indexOf(out.extraStyle) < 0) out.extraStyle = DEFAULTS.extraStyle
  out.extrasShown = clamp(out.extrasShown, 0, 4, DEFAULTS.extrasShown)
  out.rotateSeconds = clamp(out.rotateSeconds, 2, 60, DEFAULTS.rotateSeconds)
  out.notifyMinutes = clamp(out.notifyMinutes, 0, 60, DEFAULTS.notifyMinutes)
  out.soonMinutes = clamp(out.soonMinutes, 1, 180, DEFAULTS.soonMinutes)
  out.chipMaxChars = clamp(out.chipMaxChars, 8, 60, DEFAULTS.chipMaxChars)
  out.chipHorizonHours = clamp(out.chipHorizonHours, 1, 72, DEFAULTS.chipHorizonHours)
  out.tideLine = out.tideLine !== false && out.tideLine !== "false"
  out.units = out.units === "imperial" ? "imperial" : "metric"
  out.weekStart = out.weekStart === "sunday" ? "sunday" : "monday"
  out.weatherCity = String(out.weatherCity || "").trim()
  // Coordinates picked from the dropdown; anything else means "look the name up".
  var lat = out.weatherLat === "" || out.weatherLat === null ? NaN : Number(out.weatherLat)
  var lon = out.weatherLon === "" || out.weatherLon === null ? NaN : Number(out.weatherLon)
  var located = isFinite(lat) && isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180
  out.weatherLat = located ? lat : null
  out.weatherLon = located ? lon : null
  out.timerPresets = parsePresets(out.timerPresets)
  out.worldClocks = parseZones(out.worldClocks)
  return out
}

function parsePresets(text) {
  var list = Array.isArray(text) ? text : String(text || "").split(/[,\s]+/)
  var out = []
  for (var i = 0; i < list.length && out.length < 8; ++i) {
    var m = Number(list[i])
    if (validMinutes(m) && out.indexOf(m) < 0) out.push(m)
  }
  return out.length ? out : [5, 15, 25, 45]
}

// "Asia/Tokyo, Europe/London" -> ["Asia/Tokyo","Europe/London"] (max 6).
function parseZones(text) {
  var list = Array.isArray(text) ? text : String(text || "").split(/[,;\n]+/)
  var out = []
  for (var i = 0; i < list.length && out.length < 6; ++i) {
    var z = String(list[i]).trim()
    if (/^[A-Za-z0-9_+\-]+(\/[A-Za-z0-9_+\-]+){0,2}$/.test(z) && out.indexOf(z) < 0) out.push(z)
  }
  return out
}

// colors.toml -> { name: "#rrggbb" } for every hex entry.
function parseColors(raw) {
  var out = {}, lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; ++i) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
    if (m && out[m[1]] === undefined) out[m[1]] = m[2].toLowerCase()
  }
  return out
}

// ── Dates ───────────────────────────────────────────────────────────────────
function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
function sameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}
function pad(n) { return (n < 10 ? "0" : "") + n }
function clock(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
function dayKey(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }

function parse(text) {
  if (!text) return null
  var v = new Date(text)
  return isNaN(v.getTime()) ? null : v
}
// A calendar date as written, never shifted by a zone.
function parseDate(text) {
  var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(text || "")
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : null
}

// [from, until) of an item in local time, or null.
function span(item) {
  if (item.allDay) {
    var first = parseDate(item.start)
    if (!first) return null
    var last = parseDate(item.end)
    return { from: first, until: last && last > first ? last : addDays(first, 1) }
  }
  var from = parse(item.start)
  if (!from) return null
  var until = parse(item.end)
  return { from: from, until: until && until > from ? until : from }
}

function onDay(item, day) {
  var s = span(item)
  if (!s) return false
  var ds = startOfDay(day), de = addDays(ds, 1)
  if (s.until.getTime() === s.from.getTime()) return s.from >= ds && s.from < de
  return s.from < de && s.until > ds
}

// A day's rows in start order after the source selection and hide rules.
// `options`: calendarSelection (source ids; empty = all), hideAllDayEvents.
function itemsForDay(items, day, options) {
  var opt = options || {}
  var sel = Array.isArray(opt.calendarSelection) ? opt.calendarSelection : []
  var rows = []
  for (var i = 0; i < (items || []).length; ++i) {
    var it = items[i]
    if (!it || !onDay(it, day)) continue
    if (sel.length > 0 && sel.indexOf(it.sourceId) < 0) continue
    if (it.allDay && opt.hideAllDayEvents === true) continue
    rows.push(it)
  }
  rows.sort(function (a, b) {
    if (!!a.allDay !== !!b.allDay) return a.allDay ? -1 : 1
    var sa = span(a).from.getTime(), sb = span(b).from.getTime()
    return sa !== sb ? sa - sb : String(a.title).localeCompare(String(b.title))
  })
  return rows
}

// Days from `start` for `days` days that have events, each as { day, rows }.
function agendaGroups(items, start, days, options) {
  var out = [], first = startOfDay(start)
  for (var d = 0; d < days; ++d) {
    var day = addDays(first, d)
    var rows = itemsForDay(items, day, options)
    // a multi-day event is listed on its first visible day only
    if (d > 0) rows = rows.filter(function (r) { var sp = span(r); return !sp || sp.from >= startOfDay(day) })
    if (rows.length > 0) out.push({ day: day, rows: rows })
  }
  return out
}

function agendaTitle(days) {
  return days <= 1 ? "" : days === 3 ? "Next 3 days" : "Next " + days + " days"
}

// Timed events starting within `minutes` (not already started): the batch
// the helper turns into desktop notifications. { key, title, start, location, url }
function dueNotifications(items, now, minutes, options) {
  if (!(minutes > 0)) return []
  var out = [], horizon = new Date(now.getTime() + minutes * 60000)
  var rows = itemsForDay(items, now, options).concat(itemsForDay(items, addDays(now, 1), options))
  var seen = {}
  for (var i = 0; i < rows.length; ++i) {
    var r = rows[i], sp = span(r)
    if (!sp || r.allDay || sp.from <= now || sp.from > horizon) continue
    var key = r.sourceId + "|" + (r.uid || "") + "|" + r.start
    if (seen[key]) continue
    seen[key] = true
    out.push({ key: key, title: r.title, start: r.start, location: r.location || "", url: r.meetingUrl || "" })
  }
  return out
}

// Only web and mail links are ever handed to the desktop opener.
function safeUrl(u) {
  var url = String(u || "").trim()
  if (/[\u0000-\u001f\s]/.test(url) || url.length > 2000) return ""
  return /^(https?:\/\/[^\/@]+(\/|$)|mailto:[^\s@]+@[^\s@]+$|mailto:$)/i.test(url) ? url : ""
}

// "Ana, Bo +3" from an event's attendee list.
function attendeeSummary(item) {
  var list = item.attendees || [], total = item.attendeeCount || list.length
  if (total === 0) return ""
  var shown = list.slice(0, 3).join(", ")
  return total > 3 ? shown + " +" + (total - 3) : shown
}

// Index of the row happening now, else the first still ahead; all-day rows
// never count. -1 when the day is over.
function scrollTarget(rows, now) {
  var next = -1
  for (var i = 0; i < rows.length; ++i) {
    if (rows[i].allDay) continue
    var s = span(rows[i])
    if (s.from <= now && s.until > now) return i
    if (s.from > now && next < 0) next = i
  }
  return next
}

// Timed events that are on now or still ahead within `days` days, soonest
// first: [{ item, from, until, minutes, now }] (at most `limit`).
function upcoming(items, now, limit, options, days) {
  var out = []
  var horizon = Number(days) > 0 ? days : 14
  for (var d = 0; d <= horizon && out.length < 64; ++d) {
    var rows = itemsForDay(items, addDays(now, d), options)
    for (var i = 0; i < rows.length; ++i) {
      var s = span(rows[i])
      if (rows[i].allDay || s.until <= now) continue
      // multi-day timed events show on their first day only
      if (d > 0 && s.from < startOfDay(addDays(now, d))) continue
      out.push({
        item: rows[i], from: s.from, until: s.until,
        minutes: Math.max(0, Math.ceil((s.from.getTime() - now.getTime()) / 60000)),
        now: s.from <= now
      })
    }
  }
  out.sort(function (a, b) { return a.from.getTime() - b.from.getTime() })
  return out.slice(0, limit > 0 ? limit : 3)
}

function minutesLabel(min) {
  if (min < 60) return min + "m"
  var h = Math.floor(min / 60), m = min % 60
  if (h < 24) return h + "h" + (m ? pad(m) : "")
  return Math.floor(h / 24) + "d"
}

function ellipsize(text, max) {
  var t = String(text || "")
  return t.length <= max ? t : t.slice(0, Math.max(1, max - 1)).replace(/\s+$/, "") + "…"
}

// "now", "12m", "13:30" (later today), "tmrw 09:00", "Tue 09:00" for an
// upcoming() entry.
function whenLabel(next, now) {
  if (next.now) return "now"
  if (next.minutes < 60) return minutesLabel(next.minutes)
  if (sameDay(next.from, now)) return clock(next.from)
  if (sameDay(next.from, addDays(now, 1))) return "tmrw " + clock(next.from)
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][next.from.getDay()] + " " + clock(next.from)
}

// "All day", "09:00\u201310:30" or "09:00" for an item.
function timeLabel(item) {
  if (item.allDay) return "All day"
  var s = span(item)
  if (!s) return ""
  return s.until > s.from ? clock(s.from) + "\u2013" + clock(s.until) : clock(s.from)
}

// The bar chip for the next event: { text, soon, now } or null.
//   "Standup \u00b7 12m", "Standup \u00b7 now", "Lunch \u00b7 13:30", "Dentist \u00b7 Tue 09:00".
function chip(next, now, settings) {
  if (!next) return null
  var s = settings || DEFAULTS
  var title = ellipsize(next.item.title || "Untitled", s.chipMaxChars)
  return { text: title + " \u00b7 " + whenLabel(next, now), soon: next.now || next.minutes <= (s.soonMinutes || 15), now: next.now }
}

// The extras after the divider, in order: only those that are switched on
// and have something to show. `have` = { event, timer, media, weather } booleans.
function extrasFor(cfg, have) {
  var out = []
  if (cfg.showEvent && have.event) out.push("event")
  if (cfg.showTimer && have.timer) out.push("timer")
  if (cfg.showMedia && have.media) out.push("media")
  if (cfg.showWeather && have.weather) out.push("weather")
  return out
}

// What the base shows: { date, time } booleans for the clock mode.
function clockParts(mode) {
  return { date: mode === "date" || mode === "both", time: mode !== "date" }
}

// Extras that do not all fit are split into pages of `shown` and swapped
// in turn. 0 shows none.
function extraPageCount(total, shown) {
  return shown <= 0 || total <= 0 ? 0 : Math.ceil(total / shown)
}
function extraPage(extras, shown, page) {
  var pages = extraPageCount(extras.length, shown)
  if (pages === 0) return []
  var at = ((page % pages) + pages) % pages
  return extras.slice(at * shown, at * shown + shown)
}

// MPRIS loop state names: "None" -> "Playlist" -> "Track" -> "None".
function loopNext(state) {
  return state === "None" ? "Playlist" : state === "Playlist" ? "Track" : "None"
}

// The dots style: a staggered grid (every other row shifted half a column),
// one column per band. Returns { cols, rows, pitchX, pitchY, size } for a box;
// `size` is the biggest dot diameter, a little under the column pitch.
function dotGrid(w, h, cols) {
  var c = Math.max(1, Math.floor(cols))
  var pitchX = w / c
  var pitchY = pitchX * 0.866            // hex packing: rows sit closer than columns
  var rows = Math.max(1, Math.floor(h / Math.max(0.01, pitchY)))
  return { cols: c, rows: rows, pitchX: pitchX, pitchY: pitchY, size: pitchX * 0.86 }
}

// How "on" the dot in `row` (0 = bottom) is for a band at level `v` (0..1):
// a loud band lights more rows, and the row at the top of the level grows
// partway. 0..1.
function dotLevel(v, row, rows) {
  return Math.max(0, Math.min(1, Math.max(0, Math.min(1, v)) * rows - row))
}

// Dot diameter factor for a level: resting dots stay visible but tiny.
function dotScale(level) { return 0.18 + 0.82 * level }

// ── The fire style: a grid of small square cells that flicker ────────────────
// A square grid, one column per band: { cols, rows, pitch, size } for a box.
function cellGrid(w, h, cols) {
  var c = Math.max(1, Math.floor(cols))
  var pitch = w / c
  return { cols: c, rows: Math.max(1, Math.floor(h / Math.max(0.01, pitch))), pitch: pitch, size: Math.max(1, pitch * 0.84) }
}

// A cheap deterministic hash noise in [0, 1): the same (a, b, c) always gives
// the same value, so the flicker is stable within a frame and changes with `c`.
function noise(a, b, c) {
  var h = Math.imul(a | 0, 374761393) ^ Math.imul(b | 0, 668265263) ^ Math.imul(c | 0, 1274126177)
  h = Math.imul(h ^ (h >>> 13), 1103515245)
  h ^= h >>> 16
  return (h >>> 0) / 4294967296
}

// Flame height in rows for a band at level `v` (0..1); `flick` (0..1) makes
// the tongue lick up and down. Never taller than the grid.
function fireHeight(v, rows, flick) {
  return Math.min(rows, Math.max(0, Math.min(1, v)) * rows * (0.8 + 0.4 * flick))
}

// State of the cell in `row` (0 = bottom) for a flame `height` rows tall, with
// `nz` (0..1) noise for that cell. The base of a flame is solid; above that
// the cells dissolve at random, more the higher they are, so the edge is
// ragged and flickers as `nz` changes. Returns 0..1 for a lit cell (how far up
// the flame it is: 0 base, 1 tip), 1.5 for a stray spark above the flame, and
// -1 for a dark cell.
function fireState(height, row, nz) {
  if (height < 0.5) return -1
  var u = row / Math.max(1, height)
  if (u < 1) {
    var solid = 0.4
    if (u <= solid) return u
    var keep = 1 - (u - solid) / (1 - solid) * 0.92
    return nz < keep ? u : -1
  }
  if (row < height + 3 && nz > 0.985) return 1.5
  return -1
}

// Colour for a point `t` up the flame, built from the accent's own hue (h, s, l
// all 0..1) and the colours next to it on the wheel. Like a real flame it is
// hottest at the bottom: a bright, slightly shifted core, then the accent, then
// the neighbouring hue through the body, and a further neighbour fading out at
// the tips. Returns [h, s, l, a].
var FIRE_STOPS = [[0, -0.04, 0.16, 1], [0.3, 0, 0.04, 1], [0.65, 0.07, 0, 1], [1, 0.13, 0.05, 0.3]]
function fireHsl(t, h, s, l) {
  var spark = t > 1
  var u = Math.max(0, Math.min(1, t))
  var a = FIRE_STOPS[0], b = FIRE_STOPS[FIRE_STOPS.length - 1]
  for (var i = 0; i < FIRE_STOPS.length - 1; ++i)
    if (u >= FIRE_STOPS[i][0] && u <= FIRE_STOPS[i + 1][0]) { a = FIRE_STOPS[i]; b = FIRE_STOPS[i + 1]; break }
  var k = b[0] === a[0] ? 0 : (u - a[0]) / (b[0] - a[0])
  var mix = function (x, y) { return x + (y - x) * k }
  var hue = (((h + mix(a[1], b[1])) % 1) + 1) % 1
  var light = Math.max(0.12, Math.min(0.85, l + mix(a[2], b[2])))
  return [hue, Math.min(1, s * 1.05), light, mix(a[3], b[3]) * (spark ? 0.6 : 1)]
}

// A smooth SVG path through the spectrum bands for the wave / line styles.
// x is spread evenly over `w`, y comes from each 0..100 value (100 = top, 0 =
// the bottom edge at `h`). Smoothed as a Catmull-Rom spline turned into cubic
// Beziers; control points are kept inside [0, h] so it never overshoots the
// box. `closed` adds the baseline so the area under the curve can be filled.
function wavePath(values, w, h, closed) {
  var n = values ? values.length : 0
  function f(v) { return Math.round(v * 100) / 100 }
  function clampY(y) { return Math.max(0, Math.min(h, y)) }
  if (n < 2) return "M0 " + f(h) + " L" + f(w) + " " + f(h) + (closed ? " L" + f(w) + " " + f(h) + " Z" : "")
  var xs = [], ys = []
  for (var i = 0; i < n; ++i) {
    var v = Math.max(0, Math.min(100, Number(values[i]) || 0))
    xs.push(w * i / (n - 1))
    ys.push(h - v / 100 * h)
  }
  var d = "M" + f(xs[0]) + " " + f(ys[0])
  for (var j = 0; j < n - 1; ++j) {
    var p0 = Math.max(0, j - 1), p3 = Math.min(n - 1, j + 2)
    var c1x = xs[j] + (xs[j + 1] - xs[p0]) / 6, c1y = clampY(ys[j] + (ys[j + 1] - ys[p0]) / 6)
    var c2x = xs[j + 1] - (xs[p3] - xs[j]) / 6, c2y = clampY(ys[j + 1] - (ys[p3] - ys[j]) / 6)
    d += " C" + f(c1x) + " " + f(c1y) + " " + f(c2x) + " " + f(c2y) + " " + f(xs[j + 1]) + " " + f(ys[j + 1])
  }
  if (closed) d += " L" + f(xs[n - 1]) + " " + f(h) + " L" + f(xs[0]) + " " + f(h) + " Z"
  return d
}

// cava line "0;12;55;" -> [0, 12, 55] (0..100), padded/cut to `bars`.
function parseBars(line, bars) {
  var out = []
  var parts = String(line || "").split(";")
  for (var i = 0; i < parts.length && out.length < bars; ++i) {
    if (parts[i] === "") continue
    var v = Number(parts[i])
    out.push(isFinite(v) ? Math.max(0, Math.min(100, v)) : 0)
  }
  while (out.length < bars) out.push(0)
  return out
}

// ── Month grid ──────────────────────────────────────────────────────────────
// 6 weeks x 7 days starting at the week start; each cell { date, inMonth }.
function monthGrid(year, month, weekStart) {
  var first = new Date(year, month, 1)
  var offset = (first.getDay() - (weekStart === "sunday" ? 0 : 1) + 7) % 7
  var cells = []
  for (var i = 0; i < 42; ++i) {
    var d = new Date(year, month, 1 - offset + i)
    cells.push({ date: d, inMonth: d.getMonth() === month })
  }
  return cells
}

function weekdayHeaders(weekStart) {
  var all = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
  return weekStart === "sunday" ? all : all.slice(1).concat(all[0])
}

// Distinct source ids with events on a day (max 3), for the month-grid dots.
function dotsForDay(items, day, options) {
  var rows = itemsForDay(items, day, options), seen = {}, out = []
  for (var i = 0; i < rows.length && out.length < 3; ++i) {
    if (seen[rows[i].sourceId]) continue
    seen[rows[i].sourceId] = true
    out.push(rows[i].sourceId)
  }
  return out
}

// ── Sources (the nookisle rules) ────────────────────────────────────────────
var KINDS = ["file", "vdir", "ics-url", "caldav"]
var KIND_LABELS = { "file": "ICS file", "vdir": "Calendar folder", "ics-url": "iCal link (Google secret address)", "caldav": "CalDAV" }
var MAX_SOURCES = 32

function hostOf(url) {
  var m = /^[a-z]+:\/\/([^\/:?#]+)/i.exec(String(url || ""))
  return m ? m[1].toLowerCase() : ""
}

// { ok, error } for a source being added or edited.
function validateSource(src) {
  if (!src || KINDS.indexOf(src.kind) < 0) return { ok: false, error: "Pick a source type." }
  if (src.color && !/^#[0-9a-fA-F]{6}$/.test(src.color)) return { ok: false, error: "Color must look like #RRGGBB." }
  if (src.kind === "file" || src.kind === "vdir") {
    if (!String(src.path || "").trim()) return { ok: false, error: src.kind === "file" ? "Enter the path to an .ics file." : "Enter the folder path." }
    return { ok: true, error: "" }
  }
  var url = String(src.url || "").trim().replace(/^webcal:\/\//i, "https://")
  if (!/^https?:\/\//i.test(url)) return { ok: false, error: "Enter an https:// address." }
  if (/^https?:\/\/[^\/]*@/i.test(url)) return { ok: false, error: "Remove the username from the address." }
  var host = hostOf(url)
  if (/^http:/i.test(url) && host !== "localhost" && host !== "127.0.0.1") return { ok: false, error: "Only https addresses are allowed." }
  if (src.kind === "caldav" && !String(src.user || "").trim()) return { ok: false, error: "CalDAV needs a user name." }
  return { ok: true, error: "" }
}

// The web pages that go with a calendar account, for the Agenda footer:
// [{ name, url }]. Google gives Calendar, Tasks and Gmail, Outlook Calendar,
// To Do and Mail, iCloud Calendar, Reminders and Mail, Fastmail Calendar and
// Mail, Nextcloud Calendar and Tasks; an unknown server
// just gets its own front page. Local files and LAN servers have none.
// Never includes secrets: a Google feed's private key stays out of the links;
// only the account's address is used, to pick the right signed-in account.
function webLinks(src) {
  if (!src || (src.kind !== "ics-url" && src.kind !== "caldav")) return []
  var url = String(src.url || ""), host = hostOf(url)
  if (!host) return []
  if (host === "calendar.google.com" || host === "www.google.com" || host.slice(-18) === "googleusercontent.com") {
    var m = /\/(?:ical|dav|calendars)\/([^\/]+)/.exec(url), who = ""
    try { who = m ? decodeURIComponent(m[1]) : "" } catch (e) { who = "" }
    if (who.indexOf("@") < 0 || who.indexOf("group.calendar.google.com") > 0 || /\s/.test(who)) who = ""
    var q = who ? "?authuser=" + encodeURIComponent(who) : ""
    return [{ name: "Google Calendar", url: "https://calendar.google.com/calendar/u/0/r" + q },
            { name: "Google Tasks", url: "https://calendar.google.com/calendar/u/0/r/tasks" + q },
            { name: "Gmail", url: "https://mail.google.com/mail/u/0/" + q }]
  }
  if (/(^|\.)(outlook\.office365\.com|outlook\.live\.com|outlook\.office\.com)$/.test(host))
    return [{ name: "Outlook Calendar", url: "https://outlook.office.com/calendar" },
            { name: "Microsoft To Do", url: "https://to-do.office.com/tasks/" },
            { name: "Outlook Mail", url: "https://outlook.office.com/mail/" }]
  if (/(^|\.)icloud\.com$/.test(host))
    return [{ name: "iCloud Calendar", url: "https://www.icloud.com/calendar/" },
            { name: "iCloud Reminders", url: "https://www.icloud.com/reminders/" },
            { name: "iCloud Mail", url: "https://www.icloud.com/mail/" }]
  if (/(^|\.)fastmail\.com$/.test(host)) return [{ name: "Fastmail Calendar", url: "https://app.fastmail.com/calendar/" },
                                                        { name: "Fastmail", url: "https://app.fastmail.com/mail/" }]
  if (/\/remote\.php\/dav\//.test(url))
    return [{ name: "Nextcloud Calendar", url: "https://" + host + "/apps/calendar" },
            { name: "Nextcloud Tasks", url: "https://" + host + "/apps/tasks" }]
  if (src.allowLocalNetwork) return []
  return [{ name: host, url: "https://" + host + "/" }]
}

// Every account's links, without repeats, in source order.
function webLinksFor(sources) {
  var seen = {}, out = []
  for (var i = 0; i < (sources || []).length; ++i) {
    if (sources[i].enabled === false) continue
    var links = webLinks(sources[i])
    for (var j = 0; j < links.length; ++j) {
      if (seen[links[j].url]) continue
      seen[links[j].url] = true
      out.push(links[j])
    }
  }
  return out
}

function sourceTitle(src) {
  if (src.label) return src.label
  if (src.kind === "file" || src.kind === "vdir") return String(src.path || "").split("/").filter(Boolean).pop() || src.path
  return hostOf(src.url) || "Calendar"
}

function sourceDetail(src) {
  if (src.kind === "file" || src.kind === "vdir") return src.path
  return hostOf(src.url) + (src.kind === "caldav" && src.user ? " · " + src.user : "")
}

var ERROR_TEXT = {
  "auth-error": "Login or secret address was rejected",
  "secret-service-locked": "Keyring is locked or unavailable",
  "private-address": "Local address blocked (allow local network?)",
  "redirect-refused": "Redirected somewhere unsafe",
  "timeout": "Timed out",
  "network": "Network error",
  "bad-url": "Address not allowed",
  "bad-feed": "Not a calendar",
  "read-error": "Cannot read it"
}
function errorText(code) {
  if (!code) return ""
  return ERROR_TEXT[code] || (/^http-\d+$/.test(code) ? "Server said " + code.slice(5) : "Sync failed")
}

// Default accent palette for sources, from theme color names the caller maps.
var SOURCE_COLOR_NAMES = ["accent", "blue", "green", "yellow", "red", "magenta", "cyan"]
function nextColorName(sources) {
  var used = {}
  for (var i = 0; i < (sources || []).length; ++i) used[sources[i].colorName || ""] = true
  for (var j = 0; j < SOURCE_COLOR_NAMES.length; ++j) if (!used[SOURCE_COLOR_NAMES[j]]) return SOURCE_COLOR_NAMES[j]
  return SOURCE_COLOR_NAMES[(sources || []).length % SOURCE_COLOR_NAMES.length]
}

// ── Timers (omarchy-reminder) ───────────────────────────────────────────────
var UNIT = /^omarchy-reminder-[0-9]{1,5}m-[0-9]{1,12}$/

function validMinutes(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v && v >= 1 && v <= 1440 }
function validUnit(v) { return typeof v === "string" && UNIT.test(v) }
function cleanLabel(v) {
  return String(v === undefined || v === null ? "" : v).replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 80)
}

// `omarchy-reminder show --json` -> [{ unit, label, minutes, at (ms) }] soonest first.
function parseReminders(text) {
  var data
  try { data = JSON.parse(String(text)) } catch (e) { return [] }
  if (!data || typeof data !== "object" || !Array.isArray(data.reminders)) return []
  var list = []
  for (var i = 0; i < data.reminders.length && list.length < 64; ++i) {
    var e = data.reminders[i]
    if (!e || !validUnit(e.unit) || typeof e.at !== "number" || !isFinite(e.at)) continue
    var minutes = Math.floor(e.minutes) === e.minutes && e.minutes > 0 ? e.minutes : 0
    list.push({ unit: e.unit, label: cleanLabel(e.message) || (minutes > 0 ? minutes + "-min timer" : "Timer"), minutes: minutes, at: e.at * 1000 })
  }
  list.sort(function (a, b) { return a.at - b.at })
  return list
}

function soonestTimer(list, nowMs) {
  for (var i = 0; i < (list || []).length; ++i)
    if (list[i].at > nowMs) return { label: list[i].label, endsAt: list[i].at, totalMs: Math.max(60000, list[i].minutes * 60000) }
  return null
}

// Timers that vanished from the list at/after their due time (finished, not cancelled).
function finishedTimers(previous, next, nowMs) {
  var left = {}
  for (var i = 0; i < (next || []).length; ++i) left[next[i].unit] = true
  return (previous || []).filter(function (e) { return !left[e.unit] && e.at - 2000 <= nowMs })
}

function remainingLabel(ms) {
  var total = Math.max(0, Math.ceil(ms / 1000))
  var h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s = total % 60
  return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : m + ":" + pad(s)
}

// ── Weather & world clocks ──────────────────────────────────────────────────
// WMO weather code -> { text, icon } (icon is a Nerd Font glyph name key).
function weatherInfo(code, isDay) {
  var day = isDay !== false
  var c = Number(code)
  if (c === 0) return { text: "Clear", icon: day ? "sun" : "moon" }
  if (c <= 2) return { text: "Partly cloudy", icon: day ? "partly-day" : "partly-night" }
  if (c === 3) return { text: "Overcast", icon: "cloud" }
  if (c === 45 || c === 48) return { text: "Fog", icon: "fog" }
  if (c >= 51 && c <= 57) return { text: "Drizzle", icon: "drizzle" }
  if (c >= 61 && c <= 67) return { text: "Rain", icon: "rain" }
  if (c >= 71 && c <= 77) return { text: "Snow", icon: "snow" }
  if (c >= 80 && c <= 82) return { text: "Showers", icon: "rain" }
  if (c === 85 || c === 86) return { text: "Snow showers", icon: "snow" }
  if (c >= 95) return { text: "Thunderstorm", icon: "storm" }
  return { text: "Unknown", icon: "cloud" }
}

// Wall-clock time in a zone with the given UTC offset (minutes), as a Date
// whose *local getters* are the zone's wall time.
function zoneWall(nowMs, offsetMin) {
  var d = new Date(nowMs + offsetMin * 60000)
  return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds())
}

// "+3h", "-5h30" or "same" relative to the local offset (minutes).
function offsetFromLocal(offsetMin, localOffsetMin) {
  var diff = offsetMin - localOffsetMin
  if (diff === 0) return "same"
  var a = Math.abs(diff), h = Math.floor(a / 60), m = a % 60
  return (diff < 0 ? "-" : "+") + h + "h" + (m ? pad(m) : "")
}

function zoneCity(zone) {
  return String(zone).split("/").pop().replace(/_/g, " ")
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    loopNext: loopNext, parseBars: parseBars, glyph: glyph, GLYPH: GLYPH, DEFAULTS: DEFAULTS, CLOCK_MODES: CLOCK_MODES, VIZ_STYLES: VIZ_STYLES, vizLabel: vizLabel, vizStep: vizStep, wavePath: wavePath, cellGrid: cellGrid, noise: noise, fireHeight: fireHeight, fireState: fireState, fireHsl: fireHsl, dotGrid: dotGrid, dotLevel: dotLevel, dotScale: dotScale, EXTRA_STYLES: EXTRA_STYLES, parseColors: parseColors, resolveSettings: resolveSettings, parsePresets: parsePresets, parseZones: parseZones,
    startOfDay: startOfDay, addDays: addDays, sameDay: sameDay, clock: clock, dayKey: dayKey, span: span, onDay: onDay,
    itemsForDay: itemsForDay, agendaGroups: agendaGroups, agendaTitle: agendaTitle, scrollTarget: scrollTarget, upcoming: upcoming, minutesLabel: minutesLabel, ellipsize: ellipsize,
    chip: chip, whenLabel: whenLabel, timeLabel: timeLabel, extrasFor: extrasFor, extraPageCount: extraPageCount, extraPage: extraPage, clockParts: clockParts, monthGrid: monthGrid, weekdayHeaders: weekdayHeaders, dotsForDay: dotsForDay, dueNotifications: dueNotifications, safeUrl: safeUrl, attendeeSummary: attendeeSummary,
    KINDS: KINDS, KIND_LABELS: KIND_LABELS, MAX_SOURCES: MAX_SOURCES, hostOf: hostOf, validateSource: validateSource,
    SOURCE_COLOR_NAMES: SOURCE_COLOR_NAMES, webLinks: webLinks, webLinksFor: webLinksFor, sourceTitle: sourceTitle, sourceDetail: sourceDetail, errorText: errorText, nextColorName: nextColorName,
    validMinutes: validMinutes, validUnit: validUnit, cleanLabel: cleanLabel, parseReminders: parseReminders,
    soonestTimer: soonestTimer, finishedTimers: finishedTimers, remainingLabel: remainingLabel,
    weatherInfo: weatherInfo, zoneWall: zoneWall, offsetFromLocal: offsetFromLocal, zoneCity: zoneCity
  }
}
