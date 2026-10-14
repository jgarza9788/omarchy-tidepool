import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Weather for one city (Open-Meteo). The city is chosen in the settings app.
Item {
  id: tab

  required property var store
  property bool typing: false
  signal gotoTab(string name)
  signal settingsRequested(string section)

  readonly property var w: store.weather

  function handleMove(dx, dy) {}
  function handleKey(t) { return false }


  Flickable {
    anchors.fill: parent
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: parent.width
      spacing: Style.space(14)

      Row {
        width: parent.width
        spacing: Style.space(8)
        PText {
          anchors.verticalCenter: parent.verticalCenter
          text: "Weather"
          font.bold: true
          font.pixelSize: Style.font.title
        }
        PText {
          anchors.verticalCenter: parent.verticalCenter
          visible: !!tab.w
          text: tab.w ? tab.w.place.name + (tab.w.place.region ? ", " + tab.w.place.region : "") : ""
          tone: Qt.alpha(Color.popups.text, 0.55)
        }
      }

      // No city yet: the place to set it up is the settings app.
      Column {
        visible: !tab.w && tab.store.cfg.weatherCity === ""
        width: parent.width
        spacing: Style.space(10)
        PText {
          width: parent.width
          wrapMode: Text.Wrap
          elide: Text.ElideNone
          tone: Qt.alpha(Color.popups.text, 0.6)
          text: "Weather isn't set up yet."
        }
        ActionButton {
          primary: true
          icon: "cog"
          text: "Choose a city in Settings"
          onClicked: tab.settingsRequested("weather")
        }
      }

      Row {
        visible: !!tab.w
        spacing: Style.space(18)
        PText {
          anchors.verticalCenter: parent.verticalCenter
          text: tab.w ? Model.glyph(Model.weatherInfo(tab.w.current.code, tab.w.current.isDay).icon) : ""
          font.pixelSize: Style.space(46)
          tone: Color.accent
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          PText {
            text: tab.w ? Math.round(tab.w.current.temp) + "°" : ""
            font.pixelSize: Style.font.display
            font.bold: true
          }
          PText {
            text: tab.w ? Model.weatherInfo(tab.w.current.code, tab.w.current.isDay).text : ""
          }
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          PText {
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.65)
            text: tab.w ? Model.glyph("thermo") + " feels " + Math.round(tab.w.current.feels) + "°" : ""
          }
          PText {
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.65)
            text: tab.w ? Model.glyph("wind") + " " + Math.round(tab.w.current.wind) + (tab.w.units === "imperial" ? " mph" : " km/h") : ""
          }
          PText {
            visible: text !== ""
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.65)
            text: tab.w && tab.w.current.isDay ? Model.glyph("sun") + " UV " + Model.uvLabel(tab.w.current.uv) : ""
          }
        }
      }

      // Next eight hours: icon, temperature and chance of rain, spread across the width.
      Item { visible: hourRow.hours.length > 0; width: 1; height: Style.space(6) }

      Row {
        id: hourRow
        readonly property var hours: tab.w ? tab.w.hours.slice(0, 8) : []
        visible: hours.length > 0
        width: parent.width
        Repeater {
          model: hourRow.hours
          Column {
            required property var modelData
            required property int index
            width: col.width / hourRow.hours.length
            spacing: Style.space(2)
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: index === 0 ? "Now" : Qt.formatTime(new Date(modelData.time), "h AP")
              font.pixelSize: Style.font.bodySmall
              tone: Qt.alpha(Color.popups.text, 0.6)
            }
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: Model.glyph(Model.weatherInfo(modelData.code, modelData.isDay).icon)
              font.pixelSize: Style.font.display
            }
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: Math.round(modelData.temp) + "°"
              font.pixelSize: Style.font.bodySmall
            }
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: modelData.rain > 0 ? modelData.rain + "%" : ""
              font.pixelSize: Style.font.bodySmall
              tone: Color.accent
            }
          }
        }
      }

      Rectangle { visible: hourRow.hours.length > 0; width: parent.width; height: 1; color: Qt.alpha(Color.popups.text, 0.1) }

      Row {
        visible: !!tab.w
        width: parent.width
        Repeater {
          model: tab.w ? tab.w.days : []
          Column {
            required property var modelData
            required property int index
            width: col.width / 5
            spacing: Style.space(2)
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: index === 0 ? "Today" : Qt.formatDate(Model.startOfDay(new Date(modelData.date + "T12:00:00")), "ddd")
              font.pixelSize: Style.font.bodySmall
              tone: Qt.alpha(Color.popups.text, 0.6)
            }
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: Model.glyph(Model.weatherInfo(modelData.code, true).icon)
              font.pixelSize: Style.font.display
            }
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: Math.round(modelData.max) + "° / " + Math.round(modelData.min) + "°"
              font.pixelSize: Style.font.bodySmall
            }
            PText {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: modelData.rain > 0 ? modelData.rain + "%" : ""
              font.pixelSize: Style.font.bodySmall
              tone: Color.accent
            }
          }
        }
      }

      PText {
        visible: tab.store.weatherError !== ""
        text: tab.store.weatherError
        tone: Color.urgent
      }
    }
  }
}
