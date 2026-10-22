import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The Timer tab. Timers are Omarchy reminders (systemd user timers): they
// survive a shell restart and notify on their own.
Item {
  id: tab

  required property var store
  property bool typing: minutes.activeFocus || label.activeFocus
  property var host: null
  signal gotoTab(string name)
  signal settingsRequested(string section)

  function handleMove(dx, dy) {}
  function handleKey(t) { return false }

  function start(min, text) {
    if (!store.startTimer(min, text)) note = "Timers need omarchy-reminder."
    else note = ""
  }
  property string note: ""

  // A pomodoro is a chain of reminders: a work block, then a break, per cycle.
  property int cycles: 1
  function pomodoro() {
    if (!store.startPomodoro(cycles)) note = "Timers need omarchy-reminder."
    else note = ""
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(12)

    PText { text: "Start a timer"; font.bold: true; font.pixelSize: Style.font.title }

    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: tab.store.cfg.timerPresets
        ActionButton {
          required property int modelData
          text: modelData + " min"
          icon: "timer"
          onClicked: tab.start(modelData, label.text)
        }
      }
      ActionButton { text: tab.cycles > 1 ? "Pomodoro 25 + 5 \u00d7 " + tab.cycles : "Pomodoro 25 + 5"; icon: "timer"; primary: true; onClicked: tab.pomodoro() }
      ActionButton { text: "\u2212"; enabled: tab.cycles > 1; tooltip: "Fewer cycles"; onClicked: tab.cycles-- }
      ActionButton { text: "+"; enabled: tab.cycles < 8; tooltip: "More cycles"; onClicked: tab.cycles++ }
    }

    Row {
      width: parent.width
      spacing: Style.space(8)
      TextField {
        id: minutes
        width: Style.space(90)
        placeholderText: "minutes"
        validator: IntValidator { bottom: 1; top: 1440 }
        onAccepted: startCustom.clicked()
      }
      TextField {
        id: label
        width: parent.width - minutes.width - startCustom.width - parent.spacing * 2
        placeholderText: "label (optional)"
        onAccepted: startCustom.clicked()
      }
      ActionButton {
        id: startCustom
        anchors.verticalCenter: parent.verticalCenter
        text: "Start"
        primary: true
        enabled: Model.validMinutes(parseInt(minutes.text))
        onClicked: { if (enabled) { tab.start(parseInt(minutes.text), label.text); minutes.text = ""; label.text = "" } }
      }
    }

    PText {
      visible: tab.note !== ""
      text: tab.note
      tone: Color.urgent
    }

    PText { text: "Running"; font.bold: true; font.pixelSize: Style.font.title }

    ListView {
      id: list
      width: parent.width
      height: parent.height - y
      clip: true
      spacing: Style.space(6)
      model: tab.store.timers
      boundsBehavior: Flickable.StopAtBounds
      delegate: Item {
        id: t
        required property var modelData
        readonly property real total: Math.max(60000, modelData.minutes * 60000)
        property real remainingMs: Math.max(0, t.modelData.at - tab.store.nowMs)
        width: list.width
        height: Style.space(44)

        PText {
          x: 0
          width: parent.width - remaining.width - cancel.width - Style.space(16)
          text: t.modelData.label
          font.bold: true
        }
        PText {
          id: remaining
          anchors.right: cancel.left
          anchors.rightMargin: Style.space(8)
          text: Model.remainingLabel(t.remainingMs)
          tone: Color.accent
          font.bold: true
        }
        ActionButton {
          id: cancel
          anchors.right: parent.right
          icon: "close"
          onClicked: tab.store.cancelTimer(t.modelData.unit)
        }
        Rectangle {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          width: parent.width
          height: Style.space(4)
          radius: height / 2
          color: Qt.alpha(Color.popups.text, 0.08)
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, 1 - t.remainingMs / t.total))
            height: parent.height
            radius: height / 2
            color: Color.accent
          }
        }
      }

      PText {
        visible: tab.store.timers.length === 0
        anchors.centerIn: parent
        text: tab.store.timersAvailable ? "Nothing running." : "Timers need omarchy-reminder."
        tone: Qt.alpha(Color.popups.text, 0.55)
      }
    }
  }
}
