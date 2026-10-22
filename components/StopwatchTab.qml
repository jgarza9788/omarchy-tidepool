import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The Stopwatch tab, with laps. The stopwatch lives in the Store so it keeps
// running when the panel is closed.
Item {
  id: tab

  required property var store
  property bool typing: false
  property var host: null
  signal gotoTab(string name)
  signal settingsRequested(string section)

  function handleMove(dx, dy) {}
  function handleKey(t) { return false }

  property real swNow: Date.now()
  Timer {
    interval: 40
    repeat: true
    running: tab.store.swRunning && tab.visible
    onTriggered: tab.swNow = Date.now()
    onRunningChanged: if (running) tab.swNow = Date.now()
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(12)

    PText {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: Model.stopwatchLabel(tab.store.swElapsed(tab.swNow))
      font.pixelSize: Style.font.display
      font.bold: true
      tone: tab.store.swRunning ? Color.accent : Color.popups.text
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)
      ActionButton {
        text: tab.store.swRunning ? "Stop" : (tab.store.swBaseMs > 0 ? "Resume" : "Start")
        icon: tab.store.swRunning ? "pause" : "play"
        primary: true
        onClicked: tab.store.swToggle()
      }
      ActionButton {
        text: "Lap"
        icon: "pin"
        enabled: tab.store.swRunning
        onClicked: tab.store.swLap()
      }
      ActionButton {
        text: "Reset"
        icon: "refresh"
        enabled: tab.store.swRunning || tab.store.swBaseMs > 0
        onClicked: tab.store.swReset()
      }
    }

    ListView {
      id: lapList
      width: parent.width
      height: parent.height - y
      clip: true
      spacing: Style.space(4)
      model: Model.lapRows(tab.store.swLaps)
      boundsBehavior: Flickable.StopAtBounds
      delegate: Item {
        id: lap
        required property var modelData
        width: lapList.width
        height: Style.space(26)
        PText { text: "Lap " + lap.modelData.n; tone: Qt.alpha(Color.popups.text, 0.6) }
        PText {
          anchors.right: parent.right
          text: Model.stopwatchLabel(lap.modelData.total)
          font.bold: true
        }
        PText {
          anchors { right: parent.right; rightMargin: Style.space(110) }
          text: "+" + Model.stopwatchLabel(lap.modelData.split)
          tone: Color.accent
        }
      }

      PText {
        visible: tab.store.swLaps.length === 0
        anchors.centerIn: parent
        text: "No laps yet."
        tone: Qt.alpha(Color.popups.text, 0.55)
      }
    }
  }
}
