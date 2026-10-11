import QtQuick
import qs.Commons
import "../Model.js" as Model

// The day as a line: events laid on it as coloured blocks, the elapsed part
// tinted, and a marker at now. Hour ticks at 0, 6, 12, 18, 24.
Item {
  id: tide

  required property var store
  property date day: store.now

  readonly property bool isToday: Model.sameDay(day, store.now)
  readonly property real nowFrac: (store.now.getHours() * 60 + store.now.getMinutes()) / 1440
  readonly property var rows: Model.itemsForDay(store.items, day, store.calendar)
  readonly property real trackY: Style.space(10)
  readonly property real trackH: Style.space(8)

  implicitHeight: Style.space(34)

  function frac(date, edge) {
    var d0 = Model.startOfDay(day).getTime()
    return Math.max(0, Math.min(1, (date.getTime() - d0) / 86400000))
  }

  Rectangle {
    id: track
    y: tide.trackY
    width: parent.width
    height: tide.trackH
    radius: height / 2
    color: Qt.alpha(Color.popups.text, 0.08)
  }
  Rectangle {
    visible: tide.isToday
    y: tide.trackY
    width: tide.width * tide.nowFrac
    height: tide.trackH
    radius: height / 2
    color: Qt.alpha(Color.accent, 0.22)
    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
  }

  Repeater {
    model: tide.rows
    Rectangle {
      required property var modelData
      readonly property var span: Model.span(modelData)
      visible: span !== null && !modelData.allDay
      x: span ? Math.round(tide.width * tide.frac(span.from)) : 0
      y: tide.trackY
      width: span ? Math.max(Style.space(4), Math.round(tide.width * (tide.frac(span.until) - tide.frac(span.from)))) : 0
      height: tide.trackH
      radius: Style.space(2)
      color: tide.store.colorOfItem(modelData)
      opacity: span && span.until <= tide.store.now && tide.isToday ? 0.4 : 0.9
    }
  }

  Rectangle {
    visible: tide.isToday
    x: Math.round(tide.width * tide.nowFrac) - width / 2
    y: tide.trackY - Style.space(4)
    width: Style.space(2)
    height: tide.trackH + Style.space(8)
    radius: width / 2
    color: Color.accent
    Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
  }

  Repeater {
    model: [0, 6, 12, 18, 24]
    PText {
      required property int modelData
      x: Math.min(tide.width - width, Math.max(0, tide.width * modelData / 24 - width / 2))
      y: tide.trackY + tide.trackH + Style.space(3)
      text: modelData === 24 ? "24" : (modelData < 10 ? "0" : "") + modelData
      font.pixelSize: Style.font.caption
      tone: Qt.alpha(Color.popups.text, 0.45)
    }
  }
}
