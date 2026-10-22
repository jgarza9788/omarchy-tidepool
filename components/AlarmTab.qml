import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// The Alarm tab: a time of day, with repeat days or once. Alarms are systemd
// user timers (made by the helper), so they survive a shell restart.
Item {
  id: tab

  required property var store
  property bool typing: alarmTime.activeFocus || alarmLabel.activeFocus
  property var host: null
  signal gotoTab(string name)
  signal settingsRequested(string section)

  function handleMove(dx, dy) {}
  function handleKey(t) { return false }

  property string note: ""
  property var draftDays: []

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

  Column {
    anchors.fill: parent
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
      visible: tab.note !== ""
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
}
