import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The Clock tab: a switcher at the top picks World clocks, Alarm, Stopwatch or
// Timer (the iPhone's order). Timers are Omarchy reminders (systemd user
// timers): they survive a shell restart and notify on their own. Alarms are
// systemd timers too (made by the helper). The stopwatch lives in the Store so
// it keeps running when the panel is closed.
Item {
  id: tab

  required property var store
  property bool typing: minutes.activeFocus || label.activeFocus || alarmTime.activeFocus || alarmLabel.activeFocus
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

  readonly property string mode: store.clockView
  property var draftDays: []
  property real swNow: Date.now()
  Timer {
    interval: 40
    repeat: true
    running: tab.store.swRunning && tab.mode === "stopwatch" && tab.visible
    onTriggered: tab.swNow = Date.now()
    onRunningChanged: if (running) tab.swNow = Date.now()
  }
  onModeChanged: swNow = Date.now()

  function toggleDay(d) {
    var list = draftDays.slice()
    var at = list.indexOf(d)
    if (at >= 0) list.splice(at, 1)
    else list.push(d)
    draftDays = list
  }
  function addAlarm() {
    if (Model.parseTimeInput(alarmTime.text) === "") { note = "Enter a time like 7:30, 19:45 or 7am."; return }
    if (!store.addAlarm(alarmTime.text, draftDays, alarmLabel.text)) { note = "You can keep up to 20 alarms."; return }
    note = ""
    alarmTime.text = ""
    alarmLabel.text = ""
  }

  Row {
    id: switcher
    spacing: Style.space(6)
    Repeater {
      model: [{ id: "world", text: "World", icon: "globe" }, { id: "alarm", text: "Alarm", icon: "alarm" }, { id: "stopwatch", text: "Stopwatch", icon: "clock" }, { id: "timer", text: "Timer", icon: "timer" }]
      ActionButton {
        required property var modelData
        text: modelData.text
        icon: modelData.icon
        selected: tab.mode === modelData.id
        onClicked: { tab.store.clockView = modelData.id; tab.note = "" }
      }
    }
  }

  // ── World clocks ──
  ClocksTab {
    visible: tab.mode === "world"
    anchors { top: switcher.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; bottom: parent.bottom }
    store: tab.store
    host: tab.host
    onSettingsRequested: section => tab.settingsRequested(section)
  }

  // ── Timer ──
  Item {
    visible: tab.mode === "timer"
    anchors { top: switcher.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; bottom: parent.bottom }
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

  // ── Alarm ──
  Column {
    visible: tab.mode === "alarm"
    anchors { top: switcher.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; bottom: parent.bottom }
    spacing: Style.space(12)

    PText { text: "Set an alarm"; font.bold: true; font.pixelSize: Style.font.title }

    Row {
      width: parent.width
      spacing: Style.space(8)
      TextField {
        id: alarmTime
        width: Style.space(90)
        placeholderText: "7:30"
        onAccepted: addAlarmButton.clicked()
      }
      TextField {
        id: alarmLabel
        width: parent.width - alarmTime.width - addAlarmButton.width - parent.spacing * 2
        placeholderText: "label (optional)"
        onAccepted: addAlarmButton.clicked()
      }
      ActionButton {
        id: addAlarmButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Add"
        primary: true
        onClicked: tab.addAlarm()
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(6)
      Repeater {
        model: Model.DAY_NAMES
        ActionButton {
          required property string modelData
          required property int index
          text: modelData
          selected: tab.draftDays.indexOf(index) >= 0
          onClicked: tab.toggleDay(index)
        }
      }
      ActionButton { text: "Weekdays"; onClicked: tab.draftDays = [0, 1, 2, 3, 4] }
      ActionButton { text: "Every day"; onClicked: tab.draftDays = [0, 1, 2, 3, 4, 5, 6] }
      ActionButton { text: "Once"; onClicked: tab.draftDays = [] }
    }

    PText {
      visible: tab.note !== "" && tab.mode === "alarm"
      text: tab.note
      tone: Color.urgent
    }

    PText {
      text: tab.store.nextAlarm ? "Next: " + Model.nextAlarmLabel(tab.store.alarms, new Date(tab.store.nowMs)) : "Alarms"
      font.bold: true
      font.pixelSize: Style.font.title
    }

    ListView {
      id: alarmList
      width: parent.width
      height: parent.height - y
      clip: true
      spacing: Style.space(6)
      model: tab.store.alarms
      boundsBehavior: Flickable.StopAtBounds
      delegate: Item {
        id: a
        required property var modelData
        width: alarmList.width
        height: Style.space(44)
        opacity: modelData.enabled ? 1 : 0.5

        PText {
          id: when
          anchors.verticalCenter: parent.verticalCenter
          text: a.modelData.time
          font.bold: true
          font.pixelSize: Style.font.title
          tone: a.modelData.enabled ? Color.accent : Color.popups.text
        }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          x: when.width + Style.space(12)
          width: parent.width - x - toggle.width - remove.width - Style.space(16)
          PText {
            width: parent.width
            text: a.modelData.label || "Alarm"
            font.bold: true
          }
          PText {
            width: parent.width
            text: Model.alarmDaysLabel(a.modelData.days)
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.6)
          }
        }
        ActionButton {
          id: toggle
          anchors { verticalCenter: parent.verticalCenter; right: remove.left; rightMargin: Style.space(4) }
          icon: "check"
          selected: a.modelData.enabled
          tooltip: a.modelData.enabled ? "Switch off" : "Switch on"
          onClicked: tab.store.setAlarmEnabled(a.modelData.id, !a.modelData.enabled)
        }
        ActionButton {
          id: remove
          anchors { verticalCenter: parent.verticalCenter; right: parent.right }
          icon: "trash"
          tooltip: "Delete"
          onClicked: tab.store.removeAlarm(a.modelData.id)
        }
      }

      PText {
        visible: tab.store.alarms.length === 0
        anchors.centerIn: parent
        text: "No alarms."
        tone: Qt.alpha(Color.popups.text, 0.55)
      }
    }
  }

  // ── Stopwatch ──
  Column {
    visible: tab.mode === "stopwatch"
    anchors { top: switcher.bottom; topMargin: Style.space(12); left: parent.left; right: parent.right; bottom: parent.bottom }
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
