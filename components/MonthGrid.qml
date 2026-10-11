import QtQuick
import qs.Commons
import "../Model.js" as Model

// Seven columns of days. Today is an accent disc, the selected day an
// outline, and each day carries up to three dots in its calendars' colours.
Item {
  id: grid

  required property var store
  property int viewYear: store.now.getFullYear()
  property int viewMonth: store.now.getMonth()
  property date selected: store.now

  signal picked(date day)
  signal step(int months)

  readonly property var cells: Model.monthGrid(viewYear, viewMonth, store.cfg.weekStart)
  readonly property real cellW: width / 7
  readonly property real cellH: Style.space(36)

  implicitHeight: header.height + weekdays.height + cellH * 6 + Style.space(8)

  Item {
    id: header
    width: parent.width
    height: Style.space(32)

    PText {
      anchors.verticalCenter: parent.verticalCenter
      text: Qt.formatDate(new Date(grid.viewYear, grid.viewMonth, 1), "MMMM yyyy")
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      ActionButton { icon: "left"; onClicked: grid.step(-1) }
      ActionButton { text: "Today"; onClicked: grid.picked(grid.store.now) }
      ActionButton { icon: "right"; onClicked: grid.step(1) }
    }
  }

  Row {
    id: weekdays
    y: header.height + Style.space(4)
    width: parent.width
    height: Style.space(20)
    Repeater {
      model: Model.weekdayHeaders(grid.store.cfg.weekStart)
      PText {
        required property string modelData
        width: grid.cellW
        horizontalAlignment: Text.AlignHCenter
        text: modelData
        font.pixelSize: Style.font.caption
        tone: Qt.alpha(Color.popups.text, 0.5)
      }
    }
  }

  Repeater {
    model: grid.cells
    Item {
      id: cell
      required property var modelData
      required property int index
      readonly property date day: modelData.date
      readonly property bool today: Model.sameDay(day, grid.store.now)
      readonly property bool isSelected: Model.sameDay(day, grid.selected)
      readonly property var dots: Model.dotsForDay(grid.store.items, day, grid.store.calendar)

      x: (index % 7) * grid.cellW
      y: weekdays.y + weekdays.height + Math.floor(index / 7) * grid.cellH
      width: grid.cellW
      height: grid.cellH

      Rectangle {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Style.space(3)
        width: Style.space(26); height: width; radius: width / 2
        color: cell.today ? Color.accent : (hover.containsMouse ? Style.hoverFill : "transparent")
        border.width: cell.isSelected && !cell.today ? 1 : 0
        border.color: Color.accent
      }
      PText {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Style.space(3)
        text: cell.day.getDate()
        font.bold: cell.today
        tone: cell.today ? Color.popups.background
          : cell.modelData.inMonth ? Color.popups.text : Qt.alpha(Color.popups.text, 0.3)
      }
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(2)
        spacing: Style.space(2)
        Repeater {
          model: cell.dots
          Rectangle {
            required property string modelData
            width: Style.space(4); height: width; radius: width / 2
            color: grid.store.sourceColors[modelData] || Color.accent
          }
        }
      }
      MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: grid.picked(cell.day)
      }
    }
  }
}
