import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "Model.js" as Model

// The Tidepool panel: today's time and weather over a tide line of the day,
// then Agenda, Timers, Player, Weather and Calendars tabs. BarWidget.qml
// owns the bar face and hands this panel the button to anchor against and
// the shared Store.
Panel {
  id: root
  moduleName: "jgarza.tidepool"
  ipcTarget: "jgarza.tidepool"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null
  readonly property var barIdentity: hostWidget || root

  readonly property var tabs: [
    { id: "agenda", label: "Agenda", icon: "calendar" },
    { id: "timers", label: "Timers", icon: "timer" },
    { id: "player", label: "Player", icon: "music" },
    { id: "weather", label: "Weather", icon: "sun" },
    { id: "clocks", label: "Clocks", icon: "globe" }
  ]
  property string tab: "agenda"
  readonly property int tabIndex: {
    for (var i = 0; i < tabs.length; ++i) if (tabs[i].id === tab) return i
    return 0
  }

  function showTab(name) {
    if (name === "world") name = "weather"     // the old tab id
    for (var i = 0; i < tabs.length; ++i) if (tabs[i].id === name) { tab = name; break }
    open()
  }
  function stepTab(delta) {
    tab = tabs[(tabIndex + delta + tabs.length) % tabs.length].id
  }

  function open() {
    root.controller.show()
    Qt.callLater(function () {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }
  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }
  function openSettings(section) {
    close()
    if (hostWidget && typeof hostWidget.openSettings === "function") hostWidget.openSettings(section || "datetime")
  }
  function toggle() { if (root.opened) root.close(); else root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Widget-setting writes (weather city, world clocks) go through the host.
  function persist(values) {
    if (hostWidget && typeof hostWidget.persist === "function") hostWidget.persist(values)
  }

  function loadTab() {
    if (!store) return
    var props = { store: root.store }
    if (tab === "clocks") props.host = root
    tabLoader.setSource(Qt.resolvedUrl("components/" + {
      agenda: "AgendaTab", timers: "TimersTab", player: "PlayerTab", weather: "WeatherTab", clocks: "ClocksTab"
    }[tab] + ".qml"), props)
  }
  onTabChanged: loadTab()
  onStoreChanged: loadTab()
  onOpenedChanged: if (opened && store) store.refreshTimers()

  readonly property color fg: Color.bar.text
  readonly property color cardColor: Qt.tint(Color.bar.background, Qt.alpha(Color.bar.text, 0.07))
  readonly property var weather: store ? store.weather : null
  readonly property var badges: ({
    timers: !!store && store.timers.length > 0,
    player: !!store && store.playing
  })

  // Content eases in from the side the new tab sits on.
  property int lastIndex: 0
  onTabIndexChanged: { direction = tabIndex >= lastIndex ? 1 : -1; lastIndex = tabIndex }
  property int direction: 1

  TabPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    shellColor: Color.bar.background
    contentWidth: panel.fittedContentWidth(Style.space(880))
    contentHeight: panel.fittedContentHeight(Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: tabLoader.item ? tabLoader.item.typing === true : false
      onMoveRequested: function (dx, dy) {
        if (root.tab === "agenda" && tabLoader.item) tabLoader.item.handleMove(dx, dy)
        else if (dx !== 0) root.stepTab(dx)
      }
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.stepTab(direction) }
      onTextKey: function (t) {
        var n = parseInt(t)
        if (n >= 1 && n <= root.tabs.length) { root.tab = root.tabs[n - 1].id; return }
        if (tabLoader.item && tabLoader.item.handleKey(t)) return
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(10)

        // ── Hero: the time, the date, the weather ──
        Item {
          width: parent.width
          height: heroTime.height

          Column {
            id: heroTime
            PText {
              text: root.store ? Qt.formatDateTime(root.store.now, root.store.cfg.format) : ""
              font.pixelSize: Style.space(40)
              font.bold: true
              tone: root.fg
              elide: Text.ElideNone
            }
            PText {
              text: root.store ? Qt.formatDateTime(root.store.now, "dddd d MMMM") : ""
              tone: Qt.alpha(root.fg, 0.65)
              elide: Text.ElideNone
            }
          }

          Row {
            visible: !!root.weather
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)
            PText {
              anchors.verticalCenter: parent.verticalCenter
              text: root.weather ? Model.glyph(Model.weatherInfo(root.weather.current.code, root.weather.current.isDay).icon) : ""
              font.pixelSize: Style.space(32)
              tone: Color.accent
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              PText {
                text: root.weather ? Math.round(root.weather.current.temp) + "\u00b0" : ""
                font.pixelSize: Style.font.display
                font.bold: true
                tone: root.fg
                elide: Text.ElideNone
              }
              PText {
                text: root.weather ? root.weather.place.name : ""
                font.pixelSize: Style.font.bodySmall
                tone: Qt.alpha(root.fg, 0.6)
              }
            }
          }
        }

        TideBar {
          visible: !!root.store
          width: parent.width
          store: root.store
        }

        // ── Tabs merge into the card beneath them ──
        Item {
          width: parent.width
          height: parent.height - y

          TabRail {
            id: rail
            width: parent.width
            tabs: root.tabs
            current: root.tab
            badges: root.badges
            cardColor: root.cardColor
            onPicked: function (id) { root.tab = id }
            onSettingsRequested: root.openSettings()
          }

          ContentCard {
            id: card
            y: rail.tabH
            width: parent.width
            height: parent.height - rail.tabH
            fillColor: root.cardColor
            radius: Style.space(14)
            topLeftRadius: rail.firstActive ? 0 : Style.space(14)

            Loader {
              id: tabLoader
              anchors.fill: parent
              anchors.margins: Style.space(14)
              clip: true
              transform: Translate { id: shift }
              Connections {
                target: tabLoader.item
                ignoreUnknownSignals: true
                function onGotoTab(name) { root.tab = name }
                function onSettingsRequested(section) { root.openSettings(section) }
              }
              onLoaded: settle.restart()
              ParallelAnimation {
                id: settle
                NumberAnimation { target: tabLoader; property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: shift; property: "x"; from: 18 * root.direction; to: 0; duration: 260; easing.type: Easing.OutCubic }
              }
            }
          }
        }
      }
    }
  }
}
