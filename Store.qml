import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import "Model.js" as Model

// Everything the bar face, the hover peek and the panel read: calendar items,
// timers, weather, world-clock offsets and the active media player. One
// instance lives in BarWidget.qml; the pieces are handed the same object.
Item {
  id: root

  // Bar settings from shell.json, already clamped (Model.resolveSettings).
  property var cfg: Model.resolveSettings({})

  // ── Clock ────────────────────────────────────────────────────────────────
  property real nowMs: Date.now()
  readonly property date now: new Date(nowMs)

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: root.nowMs = Date.now()
  }
  // Seconds only matter while a timer is counting down.
  Timer {
    interval: 1000
    repeat: true
    running: root.timers.length > 0
    onTriggered: root.nowMs = Date.now()
  }

  // ── Theme colours (names for per-source colours) ─────────────────────────
  property var colorMap: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.colorMap = Model.parseColors(text())
    onFileChanged: reload()
    onLoadFailed: root.colorMap = ({})
  }

  function themeColor(name) {
    if (name === "accent" || !name) return Color.accent
    if (name === "foreground") return Color.foreground
    if (name === "muted") return Color.muted
    return colorMap[name] ? colorMap[name] : Color.accent
  }

  // ── Calendar ─────────────────────────────────────────────────────────────
  property var calendar: ({
    calendarSources: [], calendarSelection: [], calendarRefresh: 15,
    hideAllDayEvents: false, autoScrollToNextEvent: true, showFullEventTitles: false, agendaDays: 1
  })
  property var sourceIds: []
  property var items: []
  property var errors: ({})
  property bool syncing: false
  property string syncedAt: ""
  property string lastError: ""
  property bool loaded: false

  readonly property bool hasSources: calendar.calendarSources.length > 0

  // sourceId -> colour, re-evaluated when the theme palette changes.
  readonly property var sourceColors: {
    var map = {}
    var list = calendar.calendarSources
    for (var i = 0; i < list.length; ++i) {
      var s = list[i]
      map[sourceIds[i]] = s.colorName ? themeColor(s.colorName) : (s.color ? s.color : Color.accent)
    }
    return map
  }
  function colorOfItem(item) {
    return sourceColors[item.sourceId] || Color.accent
  }
  function colorOfSource(index) {
    var s = calendar.calendarSources[index]
    if (!s) return Color.accent
    return s.colorName ? themeColor(s.colorName) : (s.color ? s.color : Color.accent)
  }

  readonly property var upcomingList: Model.upcoming(items, now, 3, calendar)
  readonly property var nextEvent: upcomingList.length > 0 ? upcomingList[0] : null
  readonly property var nextChip: {
    if (!nextEvent) return null
    var horizonMin = cfg.chipHorizonHours * 60
    if (!nextEvent.now && nextEvent.minutes > horizonMin) return null
    return Model.chip(nextEvent, now, cfg)
  }

  function sourceError(index) {
    var id = sourceIds[index]
    return id && errors[id] ? errors[id] : ""
  }

  function applySettingsResult(r) {
    if (!r || !r.values) return false
    calendar = r.values
    sourceIds = r.ids || []
    return true
  }

  function loadAll() {
    helper("cache", {}, function (r) {
      if (r && Array.isArray(r.items)) { items = r.items; errors = r.errors || ({}); syncedAt = r.syncedAt || "" }
    })
    helper("settings-get", {}, function (r) {
      applySettingsResult(r)
      loaded = true
      sync()
    })
  }

  function sync() {
    if (syncing || !hasSources) {
      if (!hasSources) { items = []; errors = ({}) }
      return
    }
    syncing = true
    helper("sync", { sources: calendar.calendarSources, back: 7, ahead: 45 }, function (r) {
      syncing = false
      if (r && r.error) { lastError = r.error; return }
      lastError = ""
      items = r.items || []
      errors = r.errors || ({})
      syncedAt = r.syncedAt || ""
    }, 120)
  }

  // Patch the calendar settings; cb(ok) fires after the write.
  function setCalendar(patch, cb) {
    helper("settings-set", { values: patch }, function (r) {
      var ok = applySettingsResult(r)
      if (cb) cb(ok, r)
    })
  }

  // Add a source. For CalDAV the password goes to the keyring under the new
  // source's id, never into a file.
  function addSource(src, password, cb) {
    var list = calendar.calendarSources.slice()
    list.push(src)
    setCalendar({ calendarSources: list }, function (ok, r) {
      if (!ok) { if (cb) cb(false, (r && r.error) || "could not save"); return }
      var id = sourceIds[list.length - 1]
      var done = function () { sync(); if (cb) cb(true, "") }
      if (src.kind === "caldav" && password && id)
        helper("secret-set", { id: id, label: Model.sourceTitle(src), password: password }, function (s) {
          if (s && s.error) { if (cb) cb(false, s.error); return }
          done()
        })
      else done()
    })
  }

  function removeSource(index) {
    var id = sourceIds[index]
    var list = calendar.calendarSources.slice()
    list.splice(index, 1)
    setCalendar({ calendarSources: list }, function (ok) {
      if (ok && id) helper("secret-clear", { id: id })
      sync()
    })
  }

  function toggleSource(index) {
    var list = calendar.calendarSources.slice()
    var s = Object.assign({}, list[index])
    s.enabled = s.enabled === false
    list[index] = s
    setCalendar({ calendarSources: list }, function () { sync() })
  }

  function setSourceColor(index, colorName) {
    var list = calendar.calendarSources.slice()
    var s = Object.assign({}, list[index])
    s.colorName = colorName
    delete s.color
    list[index] = s
    setCalendar({ calendarSources: list })
  }

  function toggleSelected(id) {
    var sel = calendar.calendarSelection.slice()
    var at = sel.indexOf(id)
    if (at >= 0) sel.splice(at, 1); else sel.push(id)
    setCalendar({ calendarSelection: sel })
  }

  // Empty selection means every calendar is shown.
  function isVisible(id) {
    var sel = calendar.calendarSelection
    return sel.length === 0 || sel.indexOf(id) >= 0
  }
  function toggleVisible(id) {
    var all = sourceIds.slice()
    var sel = calendar.calendarSelection.length === 0 ? all.slice() : calendar.calendarSelection.slice()
    var at = sel.indexOf(id)
    if (at >= 0) sel.splice(at, 1); else sel.push(id)
    if (sel.length === 0) return            // keep at least one calendar visible
    if (sel.length === all.length) sel = []
    setCalendar({ calendarSelection: sel })
  }

  function importNookisle(cb) {
    helper("import-nookisle", {}, function (r) {
      if (r && r.error) { if (cb) cb(false, r.error); return }
      applySettingsResult(r)
      sync()
      if (cb) cb(true, r.added + " source" + (r.added === 1 ? "" : "s") + " imported")
    })
  }

  Timer {
    interval: Math.max(5, root.calendar.calendarRefresh) * 60000
    repeat: true
    running: root.hasSources
    onTriggered: root.sync()
  }

  // ── Timers (omarchy-reminder: systemd user timers) ───────────────────────
  property var timers: []
  property bool timersAvailable: true
  property string timerBuffer: ""
  property bool timerReadAgain: false
  signal timerFinished(string label)

  readonly property var soonestTimer: Model.soonestTimer(timers, nowMs)

  function refreshTimers() {
    if (timerRead.running) { timerReadAgain = true; return }
    timerBuffer = ""
    timerRead.running = true
  }
  function timersRead(exitCode) {
    timersAvailable = exitCode === 0
    var next = exitCode === 0 ? Model.parseReminders(timerBuffer) : []
    timerBuffer = ""
    var done = Model.finishedTimers(timers, next, Date.now())
    timers = next
    for (var i = 0; i < done.length; ++i) timerFinished(done[i].label)
    timerDue.stop()
    if (next.length > 0) {
      timerDue.interval = Math.max(1000, next[0].at + 1000 - Date.now())
      timerDue.start()
    }
    if (timerReadAgain) { timerReadAgain = false; Qt.callLater(refreshTimers) }
  }
  function startTimer(minutes, label) {
    if (!Model.validMinutes(minutes) || !timersAvailable) return false
    var text = Model.cleanLabel(label)
    Quickshell.execDetached(["omarchy-reminder", String(minutes)].concat(text ? [text] : []))
    timerSettle.restart()
    return true
  }
  function cancelTimer(unit) {
    if (!Model.validUnit(unit)) return false
    Quickshell.execDetached(["systemctl", "--user", "stop", unit + ".timer"])
    var rt = Quickshell.env("XDG_RUNTIME_DIR") || ""
    if (rt.charAt(0) === "/") Quickshell.execDetached(["rm", "-f", rt + "/omarchy-reminders/" + unit + ".message"])
    Quickshell.execDetached(["omarchy-shell", "-q", "omarchy.indicators", "refresh"])
    timerSettle.restart()
    return true
  }
  Process {
    id: timerRead
    command: ["omarchy-reminder", "show", "--json"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => { if (root.timerBuffer.length < 65536) root.timerBuffer += data }
    }
    onExited: (exitCode, exitStatus) => root.timersRead(exitCode)
  }
  Timer { id: timerDue; repeat: false; onTriggered: root.refreshTimers() }
  Timer { id: timerSettle; interval: 500; repeat: false; onTriggered: root.refreshTimers() }
  // Safety net for timers started or cleared from outside the shell.
  Timer { interval: 60000; repeat: true; running: true; onTriggered: root.refreshTimers() }

  // ── Weather ──────────────────────────────────────────────────────────────
  property var weather: null
  property string weatherError: ""
  function refreshWeather() {
    if (!cfg.weatherCity) { weather = null; weatherError = ""; return }
    helper("weather", { city: cfg.weatherCity, lat: cfg.weatherLat, lon: cfg.weatherLon, units: cfg.units }, function (r) {
      if (r && r.error) { weatherError = r.code === "not-found" ? "City not found" : "Weather unavailable"; return }
      weatherError = ""
      weather = r
    }, 40)
  }
  Connections {
    target: root
    function onCfgChanged() {
      if (root.weatherKey !== root.lastWeatherKey) { root.lastWeatherKey = root.weatherKey; root.refreshWeather() }
      if (root.zonesKey !== root.lastZonesKey) { root.lastZonesKey = root.zonesKey; root.refreshZones() }
    }
  }
  readonly property string weatherKey: cfg.weatherCity + "|" + cfg.weatherLat + "|" + cfg.weatherLon + "|" + cfg.units
  property string lastWeatherKey: ""
  Timer { interval: 30 * 60000; repeat: true; running: !!root.cfg.weatherCity; onTriggered: root.refreshWeather() }

  // ── World clocks ─────────────────────────────────────────────────────────
  property var zoneOffsets: ({})
  readonly property string zonesKey: cfg.worldClocks.join(",")
  property string lastZonesKey: ""
  function refreshZones() {
    var zones = cfg.worldClocks.slice()
    helper("zones", { zones: zones }, function (r) {
      zoneOffsets = (r && r.zones) ? r.zones : ({})
    })
  }
  readonly property int localOffsetMin: -new Date(nowMs).getTimezoneOffset()
  Timer { interval: 30 * 60000; repeat: true; running: root.cfg.worldClocks.length > 0; onTriggered: root.refreshZones() }

  // ── Media (MPRIS) ────────────────────────────────────────────────────────
  readonly property var players: Mpris.players ? Mpris.players.values : []
  // The player the user picked in the tab, else the one playing, else the first.
  property string preferredId: ""
  function playerId(p) { return p ? (p.dbusName || p.identity || "") : "" }
  readonly property var player: {
    var best = null
    for (var i = 0; i < players.length; ++i) {
      if (preferredId !== "" && playerId(players[i]) === preferredId) return players[i]
    }
    for (var j = 0; j < players.length; ++j) {
      if (players[j].isPlaying) return players[j]
      if (!best) best = players[j]
    }
    return best
  }
  readonly property bool hasPlayer: !!player && !!(player.trackTitle || player.trackArtist)
  readonly property bool playing: !!player && player.isPlaying
  readonly property string playerLine: {
    if (!hasPlayer) return ""
    var t = player.trackTitle || "", a = player.trackArtist || ""
    return a && t ? a + " – " + t : (t || a)
  }

  // ── Helper process plumbing ──────────────────────────────────────────────
  readonly property string helperPath: Qt.resolvedUrl("bin/tidepool-helper").toString().replace(/^file:\/\//, "")
  readonly property var helperEnv: {
    var e = { PATH: "/usr/bin", HOME: Quickshell.env("HOME"), LANG: "C.UTF-8" }
    var keep = ["XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS", "TZ"]
    for (var i = 0; i < keep.length; ++i) {
      var v = Quickshell.env(keep[i])
      if (v) e[keep[i]] = v
    }
    return e
  }

  // cb(obj) fires once; a crash or timeout yields { error }.
  function helper(cmd, payload, cb, timeoutSec) {
    oneShot.createObject(root, {
      command: ["/usr/bin/timeout", "-k", "2", String(timeoutSec || 30), "/usr/bin/python3", "-I", "-B", root.helperPath, cmd],
      payload: JSON.stringify(payload || {}),
      cb: cb || function () {}
    })
  }

  Component {
    id: oneShot
    Process {
      id: p
      property string payload: ""
      property var cb: null
      stdinEnabled: true
      clearEnvironment: true
      environment: root.helperEnv
      running: true
      onStarted: { p.write(p.payload + "\n"); p.stdinEnabled = false }
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var lines = String(text || "").trim().split("\n")
          var obj = null
          try { obj = JSON.parse(lines[lines.length - 1]) } catch (e) { obj = null }
          if (!obj || typeof obj !== "object") obj = { error: "the helper did not answer" }
          p.cb(obj)
          p.destroy(200)
        }
      }
    }
  }

  Component.onCompleted: {
    lastWeatherKey = weatherKey
    lastZonesKey = zonesKey
    loadAll()
    refreshTimers()
    refreshWeather()
    refreshZones()
  }
}
