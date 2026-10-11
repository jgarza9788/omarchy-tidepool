import QtQuick
import qs.Commons
import "../Model.js" as Model

// Hover card: today's date, the next three events, a running timer and the
// current track — a glance, not a panel.
Column {
  id: card

  required property var store
  property string fontFamily: Style.font.family

  signal settingsRequested()

  readonly property var weather: store.weather
  spacing: Style.space(8)

  Row {
    width: parent.width
    spacing: Style.space(8)

    PText {
      id: dateText
      width: parent.width - weatherText.width - parent.spacing
      text: Qt.formatDateTime(card.store.now, card.store.cfg.dateFormat)
      font.bold: true
      font.pixelSize: Style.font.title
    }
    PText {
      id: weatherText
      visible: !!card.weather
      text: card.weather
        ? Model.glyph(Model.weatherInfo(card.weather.current.code, card.weather.current.isDay).icon) + " " + Math.round(card.weather.current.temp) + "°"
        : ""
      tone: Color.accent
    }
  }

  Repeater {
    model: card.store.upcomingList
    EventRow {
      required property var modelData
      item: modelData.item
      store: card.store
      when: Model.whenLabel(modelData, card.store.now)
      expandable: false
    }
  }

  PText {
    visible: card.store.upcomingList.length === 0 && card.store.hasSources
    width: parent.width
    tone: Qt.alpha(Color.popups.text, 0.6)
    text: "Nothing coming up."
  }

  // No calendars yet: the peek is a doorway to the settings app.
  ActionButton {
    visible: !card.store.hasSources
    icon: "plus"
    text: "Add a calendar in Settings"
    primary: true
    onClicked: card.settingsRequested()
  }

  PText {
    visible: !!card.store.soonestTimer
    width: parent.width
    tone: Color.accent
    text: card.store.soonestTimer
      ? Model.glyph("timer") + "  " + card.store.soonestTimer.label + "  " + Model.remainingLabel(card.store.soonestTimer.endsAt - card.store.nowMs)
      : ""
  }
  PText {
    visible: card.store.hasPlayer
    width: parent.width
    tone: Qt.alpha(Color.popups.text, 0.7)
    text: Model.glyph(card.store.playing ? "play" : "pause") + "  " + card.store.playerLine
  }
}
