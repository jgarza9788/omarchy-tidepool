import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "components"
import "Model.js" as Model

// Tidepool: a clock that carries the next thing on your calendar.
//
// Left click opens the panel (agenda, timers, media, weather); hover shows
// a peek of the next three events; right click cycles date / time / both; middle
// click opens the timezone picker. Everything is drawn from the bar's own
// foreground and the theme accent, so it sits in the bar like the clock it
// replaces.
BarWidget {
  id: root
  moduleName: "jgarza.tidepool"

  readonly property var cfg: Model.resolveSettings(settings)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color muted: Qt.alpha(fg, 0.6)

  // ── Face: [date and/or time] | extras ─────────────────────────────────────
  readonly property string timeText: Qt.formatDateTime(store.now, cfg.format)
  readonly property string dateText: Qt.formatDateTime(store.now, cfg.dateFormat)
  readonly property var parts: Model.clockParts(cfg.clockMode)
  readonly property string baseText: {
    var out = []
    if (parts.date) out.push(dateText)
    if (parts.time) out.push(timeText)
    return out.join("  ")
  }

  readonly property var chip: store.nextChip
  readonly property var activeTimer: store.soonestTimer
  readonly property bool timerEnding: !!activeTimer && activeTimer.endsAt - store.nowMs < 60000
  readonly property string weatherText: store.weather
    ? Model.glyph(Model.weatherInfo(store.weather.current.code, store.weather.current.isDay).icon) + " " + Math.round(store.weather.current.temp) + "\u00b0"
    : ""

  // Extras after the divider: each has its own switch in the settings.
  readonly property var extras: Model.extrasFor(cfg, {
    event: !!chip, timer: !!activeTimer, media: store.hasPlayer && (store.playing || cfg.showMediaStatus), weather: weatherText !== ""
  })
  function extraText(name) {
    if (name === "event") return chip ? chip.text : ""
    if (name === "timer") return activeTimer ? Model.glyph("timer") + " " + Model.remainingLabel(activeTimer.endsAt - store.nowMs) : ""
    if (name === "media") return Model.glyph(cfg.showMediaStatus ? (store.playing ? "play" : "pause") : "media") + " " + Model.ellipsize(store.playerLine, 28)
    if (name === "weather") return weatherText
    return ""
  }
  // An event that is soon, or a timer about to ring: drawn in the accent.
  function extraAccent(name) {
    return (name === "event" && !!chip && chip.soon) || (name === "timer" && timerEnding)
  }
  function extraColor(name) {
    if (name === "event") return chip && chip.soon ? Color.accent : muted
    if (name === "timer") return timerEnding ? Color.accent : muted
    return muted
  }

  // A pulsing dot stands in for an event/timer that is about to need you
  // but whose extra is switched off.
  readonly property bool alertDot: (!!chip && chip.soon && !cfg.showEvent) || (timerEnding && !cfg.showTimer)

  // Extras are shown `extrasShown` at a time; the rest wait on other pages
  // that swap in every `rotateSeconds`.
  readonly property int pageCount: Model.extraPageCount(extras.length, cfg.extrasShown)
  property int pageIndex: 0
  readonly property int currentPage: pageCount > 0 ? pageIndex % pageCount : 0
  readonly property var pageNames: Model.extraPage(extras, cfg.extrasShown, currentPage)
  // What is on screen. It follows pageNames, except mid-swap, when it holds
  // the old page until the fade-out is done.
  property var shownNames: []
  readonly property bool hasExtras: shownNames.length > 0

  onPageNamesChanged: if (!swap.running) shownNames = pageNames
  Timer {
    interval: root.cfg.rotateSeconds * 1000
    repeat: true
    running: root.pageCount > 1 && !root.opened
    onTriggered: { root.pageIndex = (root.currentPage + 1) % root.pageCount; swap.restart() }
  }
  // Fade out, swap the page, fade in; the width follows the content.
  SequentialAnimation {
    id: swap
    NumberAnimation { target: extrasRow; property: "opacity"; to: 0; duration: 140 }
    ScriptAction { script: root.shownNames = root.pageNames }
    NumberAnimation { target: extrasRow; property: "opacity"; to: 1; duration: 180 }
  }

  // ── Day progress (the "tide") ─────────────────────────────────────────────
  readonly property real dayFraction: (store.now.getHours() * 60 + store.now.getMinutes()) / 1440
  readonly property var todayEvents: Model.itemsForDay(store.items, store.now, store.calendar)

  // ── Panel host (shape contract for shell.summon/hide/toggle routing) ───────
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  // The settings window is created fresh on every open. Reusing one window
  // object let it get stuck (after a lock/unlock the show request silently did
  // nothing), and a new one cannot be stale. The short delay lets a closing
  // panel hand focus back before the new window takes it.
  property string settingsSection: "datetime"
  function openSettings(section) {
    settingsSection = section || "datetime"
    settingsLoader.source = ""
    settingsOpener.restart()
  }
  Timer {
    id: settingsOpener
    interval: 450
    onTriggered: settingsLoader.setSource(Qt.resolvedUrl("SettingsWindow.qml"),
      { store: store, host: root, section: root.settingsSection, visible: true })
  }
  // Each extra opens the panel on its own tab; clicking it again closes it.
  readonly property var extraTabs: ({ event: "agenda", timer: "timer", media: "media", weather: "weather" })
  // The bar sends every click to the widget as one press, with no position.
  // So the extra under the pointer is tracked by hover, and a left press on
  // it opens that extra's tab.
  property string hoveredExtra: ""
  function hoverExtra(name, on) {
    if (on) hoveredExtra = name
    else if (hoveredExtra === name) hoveredExtra = ""
  }
  // Extra boxes register themselves so a click can be matched to one by its
  // position (used while the panel covers the bar and hover is not delivered).
  property var extraBoxes: ({})
  function registerExtra(name, item) { var m = Object.assign({}, extraBoxes); m[name] = item; extraBoxes = m }
  function unregisterExtra(name, item) {
    if (extraBoxes[name] !== item) return
    var m = Object.assign({}, extraBoxes); delete m[name]; extraBoxes = m
  }
  function noteBarClick(x) {
    var win = button.QsWindow.window
    var hit = ""
    if (win) for (var name in extraBoxes) {
      var it = extraBoxes[name]
      if (!it || !it.visible) continue
      var left = it.mapToItem(win.contentItem, 0, 0).x
      if (x >= left - Style.space(3) && x <= left + it.width + Style.space(3)) { hit = name; break }
    }
    hoveredExtra = hit
  }
  function openExtra(name) {
    var tab = extraTabs[name] || "agenda"
    if (opened && panelLoader.item && panelLoader.item.tab === tab) close()
    else showTab(tab)
  }
  function showTab(name) { if (panelLoader.item) panelLoader.item.showTab(name) }

  readonly property real openPanelIndicatorWidth: button.labelWidth > 0 ? button.labelWidth : button.width * 0.6
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("store" in target) target.store = store
  }

  // The face is what shell.json stores, so a cycled face survives a restart.
  function persist(values) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    // First save after the old "face" setting: write out what it meant, then drop it.
    if (entry.face !== undefined) {
      var flags = ["clockMode", "showEvent", "showTimer", "showMedia", "showWeather", "extrasShown"]
      for (var f = 0; f < flags.length; ++f) entry[flags[f]] = cfg[flags[f]]
      delete entry.face
    }
    // The media switch used to be called showMusic.
    if (entry.showMusic !== undefined) { if (entry.showMedia === undefined) entry.showMedia = cfg.showMedia; delete entry.showMusic }
    for (var k in values) entry[k] = values[k]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function cycleMode() {
    var at = Model.CLOCK_MODES.indexOf(cfg.clockMode)
    persist({ clockMode: Model.CLOCK_MODES[(at + 1) % Model.CLOCK_MODES.length] })
  }

  // ── Keeping the settings ──────────────────────────────────────────────────
  // The shell rewrites this widget's entry in shell.json when the plugin is
  // toggled off and on, which drops every option. A copy is kept in the
  // plugin's own config folder; if the entry ever comes back with nothing but
  // its id, the copy is put back.
  function userSettings(source) {
    var out = {}
    var any = false
    for (var key in source) if (key !== "id" && source[key] !== undefined && source[key] !== null) { out[key] = source[key]; any = true }
    return any ? out : null
  }
  function backupSettings() {
    var values = userSettings(root.settings)
    if (values) store.helper("widget-settings-set", { values: values }, function () {}, 10)
  }
  function restoreSettings() {
    if (userSettings(root.settings)) return backupSettings()
    store.helper("widget-settings-get", {}, function (r) {
      // Checked again now: the shell may have filled the entry in while we asked.
      if (!r || !r.values || userSettings(root.settings)) return
      var saved = userSettings(r.values)
      if (saved) root.persist(saved)
    }, 10)
  }
  Timer { id: backupSoon; interval: 800; onTriggered: root.backupSettings() }

  onBarChanged: injectPanel()
  onSettingsChanged: { injectPanel(); backupSoon.restart() }
  Component.onCompleted: { shownNames = pageNames; restoreSettings() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Store {
    id: store
    cfg: root.cfg
  }

  Loader { id: settingsLoader }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "jgarza.tidepool"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function tab(name: string): void { root.showTab(name) }
    function sync(): void { store.sync() }
    // Make the Media tab follow an app, by (part of) its name, e.g. `app plezy`. "" resets it.
    function app(name: string): string {
      var want = String(name || "").toLowerCase()
      if (want === "") { store.preferredId = ""; return "auto" }
      for (var i = 0; i < store.players.length; ++i) {
        var p = store.players[i]
        if ((p.identity || "").toLowerCase().indexOf(want) >= 0 || (p.dbusName || "").toLowerCase().indexOf(want) >= 0) {
          store.preferredId = store.playerId(p)
          return p.identity || p.dbusName
        }
      }
      return "no such app"
    }
    function timer(minutes: int, label: string): void { store.startTimer(minutes, label) }
    function cycleMode(): void { root.cycleMode() }
    function settings(section: string): void { root.openSettings(section) }
  }

  // ── Bar button ────────────────────────────────────────────────────────────
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    fixedWidth: root.vertical ? -1 : Math.ceil(root.contentWidth + Style.spaceReal(8.75) * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot * 2 : -1

    onPressed: function (b) {
      peekDelay.stop()
      if (b === Qt.RightButton) root.cycleMode()
      else if (b === Qt.MiddleButton) { if (root.bar) root.bar.run("omarchy-menu-timezone") }
      else if (root.hoveredExtra !== "") { peek.open = false; root.openExtra(root.hoveredExtra) }
      else root.togglePanel()
    }

    // Vertical bars: just the time, stacked.
    Column {
      visible: root.vertical
      anchors.centerIn: parent
      Repeater {
        model: Qt.formatDateTime(store.now, "HH\nmm").split("\n")
        Text {
          textFormat: Text.PlainText
          required property string modelData
          anchors.horizontalCenter: parent.horizontalCenter
          text: modelData
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    Row {
      id: face
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(8)

      // Pulses when something needs you soon and its extra is hidden.
      Rectangle {
        id: dot
        visible: root.alertDot
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(6); height: width; radius: width / 2
        color: Color.accent
        SequentialAnimation on opacity {
          running: dot.visible
          loops: Animation.Infinite
          NumberAnimation { from: 1; to: 0.25; duration: 900; easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.25; to: 1; duration: 900; easing.type: Easing.InOutSine }
        }
      }

      // The base: date and/or time.
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.baseText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      // [divider] extra [divider] extra …, then a dot per page when some wait.
      Row {
        id: extrasRow
        visible: root.hasExtras
        leftPadding: -Style.space(8)     // the face row already spaces the base from this
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Repeater {
          model: root.shownNames
          Row {
            id: entry
            required property string modelData
            required property int index
            readonly property bool boxed: root.cfg.extraStyle !== "plain"
            spacing: 0
            anchors.verticalCenter: parent.verticalCenter

            // Room on both sides of a divider. Boxed extras need only the
            // first one (base | extras); the boxes separate themselves.
            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: entry.boxed && entry.index > 0 ? Style.space(6) : Style.space(1) + Style.space(16)
              height: Style.space(12)
              Rectangle {
                visible: !entry.boxed || entry.index === 0
                anchors.centerIn: parent
                width: Math.max(1, Style.space(1))
                height: parent.height
                color: Qt.alpha(root.fg, 0.28)
              }
            }

            // The extra itself, plain or in a border / button.
            Rectangle {
              id: box
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: content.implicitWidth + (entry.boxed ? Style.space(14) : 0)
              implicitHeight: content.implicitHeight + (entry.boxed ? Style.space(6) : 0)
              width: implicitWidth
              height: implicitHeight
              radius: Style.space(7)
              readonly property bool hot: boxHover.hovered
              color: !entry.boxed ? "transparent"
                : root.cfg.extraStyle === "button" ? Qt.alpha(root.fg, hot ? 0.16 : 0.08)
                : hot ? Qt.alpha(root.fg, 0.06) : "transparent"
              border.width: entry.boxed ? 1 : 0
              border.color: root.extraAccent(entry.modelData) ? Qt.alpha(Color.accent, 0.8) : Qt.alpha(root.fg, root.cfg.extraStyle === "button" ? 0.14 : 0.3)
              Behavior on color { ColorAnimation { duration: 140 } }
              Behavior on border.color { ColorAnimation { duration: 200 } }
              Behavior on implicitWidth { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              Component.onCompleted: root.registerExtra(entry.modelData, box)
              Component.onDestruction: root.unregisterExtra(entry.modelData, box)

              Row {
                id: content
                anchors.centerIn: parent
                spacing: Style.space(5)

                // A few spectrum bars beside the track while it plays.
                Visualizer {
                  id: miniViz
                  visible: entry.modelData === "media" && root.cfg.miniVisualizer && root.cfg.visualizerStyle !== "none" && store.playing && available
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? Style.space(22) : 0
                  height: Style.space(12)
                  implicitHeight: height
                  active: entry.modelData === "media" && root.cfg.miniVisualizer && root.cfg.visualizerStyle !== "none" && store.playing
                  config: "cava-mini.conf"
                  styleName: root.cfg.visualizerStyle
                  bars: 8
                  gap: Style.space(1)
                  minH: Style.space(2)
                }

                Text {
                  textFormat: Text.PlainText
                  id: label
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.extraText(entry.modelData)
                  color: root.extraColor(entry.modelData)
                  font.family: root.fontFamily
                  font.pixelSize: button.fontSize
                  font.bold: root.extraAccent(entry.modelData) && entry.modelData === "event"
                  renderType: Text.NativeRendering
                  Behavior on color { ColorAnimation { duration: 200 } }
                }
              }

              // Which extra the pointer is over (the press itself is handled by
              // the button above, which opens this extra's tab).
              HoverHandler {
                id: boxHover
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: root.hoverExtra(entry.modelData, hovered)
              }
            }
          }
        }

        // Pages that are not showing.
        Row {
          visible: root.pageCount > 1
          anchors.verticalCenter: parent.verticalCenter
          leftPadding: Style.space(8)
          spacing: Style.space(3)
          Repeater {
            model: root.pageCount > 1 ? root.pageCount : 0
            Rectangle {
              required property int index
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(4); height: width; radius: width / 2
              color: index === root.currentPage ? Color.accent : Qt.alpha(root.fg, 0.3)
              Behavior on color { ColorAnimation { duration: 200 } }
            }
          }
        }
      }
    }

    // The tide line: the day as a hairline, events as ticks, now as the fill.
    Item {
      id: tide
      visible: root.cfg.tideLine && !root.vertical
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.spaceReal(8.75)
      anchors.rightMargin: Style.spaceReal(8.75)
      anchors.bottomMargin: Style.space(2)
      height: Style.space(4)

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(1, Style.space(1))
        color: Qt.alpha(root.fg, 0.14)
      }
      Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: Math.max(1, Style.space(1))
        width: parent.width * root.dayFraction
        color: Qt.alpha(Color.accent, 0.8)
        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
      }
      Repeater {
        model: root.todayEvents.slice(0, 16)
        Rectangle {
          required property var modelData
          readonly property var span: Model.span(modelData)
          readonly property real startFrac: span ? Math.max(0, Math.min(1, (span.from.getHours() * 60 + span.from.getMinutes()) / 1440)) : 0
          visible: span !== null && !modelData.allDay
          x: Math.round((tide.width - 1) * startFrac)
          anchors.bottom: parent.bottom
          width: Math.max(1, Style.space(1)); height: Style.space(4)
          color: store.colorOfItem(modelData)
          opacity: 0.9
        }
      }
    }
  }

  // Width the face wants, animated so chips slide in rather than snap.
  property real contentWidth: face.implicitWidth
  Behavior on contentWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

  // ── Hover peek ────────────────────────────────────────────────────────────
  readonly property bool pointerOver: button.tooltipHovered || peek.containsMouse
  onPointerOverChanged: {
    if (pointerOver && cfg.peekOnHover && !opened) { peekClose.stop(); peekDelay.restart() }
    else { peekDelay.stop(); peekClose.restart() }
  }
  onOpenedChanged: if (opened) { peekDelay.stop(); peek.open = false }
  Timer { id: peekDelay; interval: 280; onTriggered: if (root.pointerOver && !root.opened) peek.open = true }
  Timer { id: peekClose; interval: 160; onTriggered: if (!root.pointerOver) peek.open = false }

  TabPeek {
    id: peek
    anchorItem: button
    bar: root.bar
    contentWidth: Style.space(290)
    contentHeight: peekCard.implicitHeight + padding * 2

    PeekCard {
      id: peekCard
      width: parent.width
      store: store
      fontFamily: root.fontFamily
      onSettingsRequested: { peek.open = false; root.openSettings("calendars") }
    }
  }
}
