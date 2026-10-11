import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "Model.js" as Model

// Tidepool's settings app: a fixed-size floating window (like Nookisle's),
// in the bar's colours. Every widget option lives here; changes are saved to
// the widget's shell.json entry as you make them. Calendars reuse the same
// source editor as the panel.
FloatingWindow {
  id: win

  required property var store
  property var host: null
  property string section: "datetime"
  // Old section names still work (shell commands, saved links).
  onSectionChanged: if (section === "general") section = "datetime"
    else if (section === "music") section = "media"
    else if (section === "timers") section = "timer"

  readonly property var cfg: store ? store.cfg : Model.resolveSettings({})
  readonly property var cal: store ? store.calendar : ({})
  // Sidebar order: the bar itself, then each extra (in the order of the
  // switches in Bar extras), then what the panel shows. `group` starts a group.
  readonly property var sections: [
    { id: "datetime", label: "Date & time", icon: "clock", group: "Bar" },
    { id: "extras", label: "Bar extras", icon: "plus" },
    { id: "appearance", label: "Appearance", icon: "palette" },
    { id: "event", label: "Next event", icon: "calendar", group: "Extras" },
    { id: "timer", label: "Timer", icon: "timer" },
    { id: "media", label: "Media", icon: "media" },
    { id: "weather", label: "Weather", icon: "sun" },
    { id: "calendars", label: "Calendars", icon: "calendar-plus", group: "Panel" },
    { id: "agenda", label: "Agenda", icon: "calendar" },
    { id: "clocks", label: "World clocks", icon: "globe" }
  ]
  function set(values) { if (host) host.persist(values) }
  title: "Tidepool Settings"
  implicitWidth: Style.space(860)
  implicitHeight: Style.space(640)
  minimumSize: Qt.size(implicitWidth, implicitHeight)
  maximumSize: Qt.size(implicitWidth, implicitHeight)
  color: Color.bar.background

  // ── Small controls ──
  component Choice: Row {
    id: choice
    property var options: []
    property string value: ""
    signal picked(string value)
    spacing: Style.space(4)
    Repeater {
      model: choice.options
      ActionButton {
        required property var modelData
        text: modelData.label
        selected: choice.value === modelData.value
        onClicked: choice.picked(modelData.value)
      }
    }
  }
  component Stepper: Row {
    id: stepper
    property int value: 0
    property int from: 0
    property int to: 100
    property int step: 1
    property string suffix: ""
    signal changed(int value)
    spacing: Style.space(6)
    ActionButton { icon: "left"; enabled: stepper.value > stepper.from; onClicked: stepper.changed(Math.max(stepper.from, stepper.value - stepper.step)) }
    PText {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(64)
      horizontalAlignment: Text.AlignHCenter
      text: stepper.value + stepper.suffix
      font.bold: true
    }
    ActionButton { icon: "right"; enabled: stepper.value < stepper.to; onClicked: stepper.changed(Math.min(stepper.to, stepper.value + stepper.step)) }
  }
  component Field: TextField {
    id: field
    property string current: ""
    signal committed(string text)
    width: Style.space(260)
    text: current
    onCurrentChanged: if (!activeFocus) text = current
    onEditingFinished: if (text !== current) committed(text)
  }
  component Switch: ToggleSwitch {
    foreground: Color.popups.text
    // The bare switch has no keyboard handling of its own.
    activeFocusOnTab: true
    hasCursor: activeFocus
    Keys.onSpacePressed: toggled()
    Keys.onReturnPressed: toggled()
    Keys.onEnterPressed: toggled()
  }

  Row {
    anchors.fill: parent

    // ── Sidebar ──
    Rectangle {
      width: Style.space(210)
      height: parent.height
      color: Qt.tint(Color.bar.background, Qt.alpha(Color.bar.text, 0.04))

      Column {
        anchors.fill: parent
        anchors.margins: Style.space(14)
        spacing: Style.space(4)

        PText { text: "Tidepool"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
        PText { text: "Settings"; tone: Qt.alpha(Color.popups.text, 0.55); elide: Text.ElideNone }
        Item { width: 1; height: Style.space(14) }

        Repeater {
          model: win.sections
          Column {
            id: navItem
            required property var modelData
            width: parent.width
            spacing: Style.space(2)

            // A small caption where a new group starts.
            PText {
              visible: !!navItem.modelData.group
              width: parent.width
              topPadding: navItem.modelData.group === "Bar" ? 0 : Style.space(12)
              leftPadding: Style.space(12)
              text: (navItem.modelData.group || "").toUpperCase()
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideNone
              tone: Qt.alpha(Color.popups.text, 0.4)
            }
            ActionButton {
              width: parent.width
              leftAlign: true
              icon: navItem.modelData.icon
              text: navItem.modelData.label
              selected: win.section === navItem.modelData.id
              onClicked: win.section = navItem.modelData.id
            }
          }
        }
      }
    }

    // ── Pages ──
    Item {
      width: parent.width - Style.space(210)
      height: parent.height

      // Date & time
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "datetime"
        contentHeight: datetime.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: datetime
          width: parent.width
          PText { text: "Date & time"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }

          SettingRow {
            label: "Show"
            description: "The base of the widget. Right-click the bar to cycle it."
            Choice {
              value: win.cfg.clockMode
              options: [{ value: "time", label: "Time" }, { value: "date", label: "Date" }, { value: "both", label: "Date + time" }]
              onPicked: function (v) { win.set({ clockMode: v }) }
            }
          }
          SettingRow {
            label: "Time format"
            description: "Qt date format, e.g. HH:mm or h:mm AP."
            Field { current: win.cfg.format; onCommitted: function (t) { win.set({ format: t || "HH:mm" }) } }
          }
          SettingRow {
            label: "Date format"
            description: "e.g. ddd d MMM. Also used by the hover peek."
            Field { current: win.cfg.dateFormat; onCommitted: function (t) { win.set({ dateFormat: t || "ddd d MMM" }) } }
          }
        }
      }

      // Bar extras
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "extras"
        contentHeight: extras.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: extras
          width: parent.width
          PText { text: "Bar extras"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }

          PText { text: "What shows after the divider"; font.bold: true; tone: Color.accent; topPadding: Style.space(6); bottomPadding: Style.space(2); elide: Text.ElideNone }
          SettingRow {
            label: "Next event"
            description: "A chip like \u201cStandup \u00b7 12m\u201d, in the accent colour when it is soon. Options are in the Next event section."
            Switch { checked: win.cfg.showEvent; onToggled: win.set({ showEvent: !win.cfg.showEvent }) }
          }
          SettingRow {
            label: "Timer"
            description: "The countdown of the soonest running timer. Options are in the Timer section."
            Switch { checked: win.cfg.showTimer; onToggled: win.set({ showTimer: !win.cfg.showTimer }) }
          }
          SettingRow {
            label: "Media"
            description: "What is playing: a track, a video, a podcast. Options are in the Media section."
            Switch { checked: win.cfg.showMedia; onToggled: win.set({ showMedia: !win.cfg.showMedia }) }
          }
          SettingRow {
            label: "Weather"
            description: "Icon and temperature. Needs a city: set it in the Weather section."
            Switch { checked: win.cfg.showWeather; onToggled: win.set({ showWeather: !win.cfg.showWeather }) }
          }
          PText { text: "How they show"; font.bold: true; tone: Color.accent; topPadding: Style.space(16); bottomPadding: Style.space(2); elide: Text.ElideNone }
          SettingRow {
            label: "Extras shown at once"
            description: "0 hides extras and the divider. If more are switched on than fit, they swap in turn, with dots for the rest."
            Stepper { value: win.cfg.extrasShown; from: 0; to: 4; onChanged: function (v) { win.set({ extrasShown: v }) } }
          }
          SettingRow {
            label: "Style"
            description: "Draw each extra in an outlined box, or as a filled button."
            Choice {
              value: win.cfg.extraStyle
              options: [{ value: "plain", label: "Plain" }, { value: "border", label: "Border" }, { value: "button", label: "Button" }]
              onPicked: function (v) { win.set({ extraStyle: v }) }
            }
          }
          SettingRow {
            label: "Swap every"
            description: "Seconds per page when extras swap."
            Stepper { value: win.cfg.rotateSeconds; from: 2; to: 60; suffix: " s"; onChanged: function (v) { win.set({ rotateSeconds: v }) } }
          }
        }
      }

      // Next event
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "event"
        contentHeight: eventPage.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: eventPage
          width: parent.width
          PText { text: "Next event"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }
          SettingRow {
            label: "Show on the bar"
            description: "Also switched in Bar extras."
            Switch { checked: win.cfg.showEvent; onToggled: win.set({ showEvent: !win.cfg.showEvent }) }
          }
          SettingRow {
            label: "Notify before events"
            description: "A desktop notification this many minutes before an event starts, with the room and call link. 0 turns it off."
            Stepper { value: win.cfg.notifyMinutes; from: 0; to: 60; step: 5; suffix: " min"; onChanged: function (v) { win.set({ notifyMinutes: v }) } }
          }
          SettingRow {
            label: "\u201cSoon\u201d threshold"
            description: "Events this close are highlighted in the accent colour."
            Stepper { value: win.cfg.soonMinutes; from: 1; to: 180; step: 5; suffix: " min"; onChanged: function (v) { win.set({ soonMinutes: v }) } }
          }
          SettingRow {
            label: "Chip horizon"
            description: "Only show the next-event chip when it starts within this long."
            Stepper { value: win.cfg.chipHorizonHours; from: 1; to: 72; suffix: " h"; onChanged: function (v) { win.set({ chipHorizonHours: v }) } }
          }
          SettingRow {
            label: "Chip title length"
            description: "Longer event titles are shortened."
            Stepper { value: win.cfg.chipMaxChars; from: 8; to: 60; step: 2; suffix: " ch"; onChanged: function (v) { win.set({ chipMaxChars: v }) } }
          }
        }
      }

      // Appearance
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "appearance"
        contentHeight: appearance.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: appearance
          width: parent.width
          PText { text: "Appearance"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }

          SettingRow {
            label: "Hover peek"
            description: "Show the next three events when hovering."
            Switch { checked: win.cfg.peekOnHover; onToggled: win.set({ peekOnHover: !win.cfg.peekOnHover }) }
          }
          SettingRow {
            label: "Day-progress line"
            description: "A hairline under the widget that fills as the day passes."
            Switch { checked: win.cfg.tideLine; onToggled: win.set({ tideLine: !win.cfg.tideLine }) }
          }
        }
      }

      // Media
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "media"
        contentHeight: media.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: media
          width: parent.width
          PText { text: "Media"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }

          SettingRow {
            label: "Show on the bar"
            description: "Also switched in Bar extras. Turn it off and the options below have no effect."
            Switch { checked: win.cfg.showMedia; onToggled: win.set({ showMedia: !win.cfg.showMedia }) }
          }
          SettingRow {
            label: "Show play / pause status"
            description: "A play or pause icon before the title. The extra then stays on the bar while paused; without it, it only shows while playing."
            Switch { checked: win.cfg.showMediaStatus; onToggled: win.set({ showMediaStatus: !win.cfg.showMediaStatus }) }
          }
          SettingRow {
            label: "Mini visualizer"
            description: "A few live spectrum bars next to the title while it plays. Runs cava in the background, only while something is playing."
            Switch { checked: win.cfg.miniVisualizer; onToggled: win.set({ miniVisualizer: !win.cfg.miniVisualizer }) }
          }
          SettingRow {
            label: "Visualizer style"
            description: "How the spectrum is drawn, in the Media tab and on the bar."
            Choice {
              value: win.cfg.visualizerStyle
              options: [{ value: "bars", label: "Bars" }, { value: "mirror", label: "Mirror" }, { value: "dots", label: "Dots" }, { value: "wave", label: "Wave" }, { value: "line", label: "Line" }, { value: "fire", label: "Fire" }]
              onPicked: function (v) { win.set({ visualizerStyle: v }) }
            }
          }

          // A live preview, so each style can be seen as you pick it.
          Rectangle {
            width: parent.width
            height: Style.space(110)
            radius: Style.space(10)
            color: Qt.alpha(Color.popups.text, 0.05)
            Visualizer {
              anchors.fill: parent
              anchors.margins: Style.space(12)
              active: win.section === "media" && !!win.store && win.store.playing
              bars: 48
              styleName: win.cfg.visualizerStyle
            }
            PText {
              visible: !win.store || !win.store.playing
              anchors.centerIn: parent
              text: "Play something to see a preview."
              tone: Qt.alpha(Color.popups.text, 0.5)
            }
          }

          PText {
            width: parent.width
            topPadding: Style.space(14)
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.6)
            text: "Works with any MPRIS player (Spotify, mpv, jellyfin-tui, a browser…). The Media tab in the panel has the full controls."
          }
        }
      }

      // Calendars
      Item {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "calendars"
        Loader {
          anchors.fill: parent
          active: win.section === "calendars"
          sourceComponent: SourcesTab { store: win.store }
        }
      }

      // Agenda
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "agenda"
        contentHeight: agenda.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: agenda
          width: parent.width
          PText { text: "Agenda"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }

          SettingRow {
            label: "Show"
            description: "How far ahead the Agenda tab looks, starting from the selected day. More than one day lists events grouped by day."
            Choice {
              value: String(win.cal.agendaDays)
              options: [{ value: "1", label: "Day" }, { value: "3", label: "3 days" }, { value: "7", label: "7 days" }, { value: "14", label: "14 days" }, { value: "30", label: "30 days" }]
              onPicked: function (v) { win.store.setCalendar({ agendaDays: parseInt(v) }) }
            }
          }
          SettingRow {
            label: "Week starts on"
            description: "For the month grid."
            Choice {
              value: win.cfg.weekStart
              options: [{ value: "monday", label: "Monday" }, { value: "sunday", label: "Sunday" }]
              onPicked: function (v) { win.set({ weekStart: v }) }
            }
          }
          SettingRow {
            label: "Hide all-day events"
            Switch { checked: win.cal.hideAllDayEvents; onToggled: win.store.setCalendar({ hideAllDayEvents: !win.cal.hideAllDayEvents }) }
          }
          SettingRow {
            label: "Scroll to the next event"
            description: "On a single day, jump the list to what is on now or next."
            Switch { checked: win.cal.autoScrollToNextEvent; onToggled: win.store.setCalendar({ autoScrollToNextEvent: !win.cal.autoScrollToNextEvent }) }
          }
          SettingRow {
            label: "Show full event titles"
            description: "Wrap long titles instead of cutting them."
            Switch { checked: win.cal.showFullEventTitles; onToggled: win.store.setCalendar({ showFullEventTitles: !win.cal.showFullEventTitles }) }
          }
        }
      }

      // Weather
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "weather"
        contentHeight: weather.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: weather
          width: parent.width
          PText { text: "Weather"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }
          SettingRow {
            label: "Show on the bar"
            description: "Also switched in Bar extras."
            Switch { checked: win.cfg.showWeather; onToggled: win.set({ showWeather: !win.cfg.showWeather }) }
          }
          SettingRow {
            label: "City"
            description: "Start typing and pick from the list. Leave empty to hide weather."
            CityPicker {
              store: win.store
              current: win.cfg.weatherCity
              onChosen: function (place) { win.set({ weatherCity: place.label, weatherLat: place.lat, weatherLon: place.lon }) }
              onCleared: win.set({ weatherCity: "", weatherLat: "", weatherLon: "" })
            }
          }
          SettingRow {
            label: "Units"
            Choice {
              value: win.cfg.units
              options: [{ value: "metric", label: "°C, km/h" }, { value: "imperial", label: "°F, mph" }]
              onPicked: function (v) { win.set({ units: v }) }
            }
          }
        }
      }

      // World clocks
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "clocks"
        contentHeight: clocks.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: clocks
          width: parent.width
          PText { text: "World clocks"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }
          PText {
            width: parent.width
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            bottomPadding: Style.space(8)
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.6)
            text: "Search for a city or time zone and pick it. Up to 6 show in the Clocks tab."
          }

          // The zones you have, with a way to drop each.
          Repeater {
            model: win.cfg.worldClocks
            SettingRow {
              id: zrow
              required property string modelData
              label: Model.zoneCity(modelData)
              description: modelData
              ActionButton {
                icon: "close"
                text: "Remove"
                onClicked: win.set({ worldClocks: win.cfg.worldClocks.filter(function (z) { return z !== zrow.modelData }).join(", ") })
              }
            }
          }
          PText {
            visible: win.cfg.worldClocks.length === 0
            width: parent.width
            topPadding: Style.space(4)
            bottomPadding: Style.space(10)
            text: "No world clocks yet."
            tone: Qt.alpha(Color.popups.text, 0.55)
          }

          Item { width: 1; height: Style.space(10) }
          ZonePicker {
            width: parent.width
            store: win.store
            full: win.cfg.worldClocks.length >= 6
            onChosen: function (place) {
              win.set({ worldClocks: Model.parseZones(win.cfg.worldClocks.concat([place.zone])).join(", ") })
            }
          }
        }
      }

      // Timer
      Flickable {
        anchors.fill: parent
        anchors.margins: Style.space(22)
        visible: win.section === "timer"
        contentHeight: timers.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: timers
          width: parent.width
          PText { text: "Timer"; font.pixelSize: Style.font.heading; font.bold: true; elide: Text.ElideNone }
          Item { width: 1; height: Style.space(8) }
          SettingRow {
            label: "Show on the bar"
            description: "Also switched in Bar extras."
            Switch { checked: win.cfg.showTimer; onToggled: win.set({ showTimer: !win.cfg.showTimer }) }
          }
          SettingRow {
            label: "Presets"
            description: "Comma-separated minutes for the quick-start buttons, e.g. 5, 15, 25, 45."
            Field {
              current: win.cfg.timerPresets.join(", ")
              onCommitted: function (t) { win.set({ timerPresets: Model.parsePresets(t).join(",") }) }
            }
          }
          PText {
            width: parent.width
            topPadding: Style.space(12)
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.6)
            text: "Timers are Omarchy reminders (systemd user timers). They keep running if the shell restarts and notify on their own."
          }
        }
      }
    }
  }
}
