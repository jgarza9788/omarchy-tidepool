import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// Calendar sources and the options that shape the agenda. The source kinds
// and their rules are Nookisle's: ICS file, calendar folder, iCal link (a
// Google "secret address in iCal format") and CalDAV, whose password goes to
// the keyring and never to a file.
Item {
  id: tab

  required property var store
  property bool typing: pathField.activeFocus || urlField.activeFocus || userField.activeFocus
    || passField.activeFocus || labelField.activeFocus
  signal gotoTab(string name)
  signal settingsRequested(string section)


  property string kind: "ics-url"
  property bool allowLocal: false
  property string formError: ""
  property string notice: ""
  property bool busy: false

  readonly property bool remote: kind === "ics-url" || kind === "caldav"
  readonly property var sources: store.calendar.calendarSources

  function handleMove(dx, dy) {}
  function handleKey(t) { return false }

  function reset() {
    pathField.text = ""; urlField.text = ""; userField.text = ""; passField.text = ""; labelField.text = ""
    allowLocal = false; formError = ""
  }
  function add() {
    var src = { kind: kind, label: labelField.text.trim(), colorName: Model.nextColorName(sources), enabled: true }
    if (remote) {
      src.url = urlField.text.trim().replace(/^webcal:\/\//i, "https://")
      if (kind === "caldav") src.user = userField.text.trim()
      if (allowLocal) src.allowLocalNetwork = true
    } else {
      src.path = pathField.text.trim()
    }
    var check = Model.validateSource(src)
    if (!check.ok) { formError = check.error; return }
    if (sources.length >= Model.MAX_SOURCES) { formError = "That is the most calendars you can add."; return }
    formError = ""; busy = true
    store.addSource(src, passField.text, function (ok, err) {
      busy = false
      if (ok) { reset(); notice = "Added. Syncing…" }
      else formError = err
    })
  }

  Flickable {
    anchors.fill: parent
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: parent.width - Style.space(4)
      spacing: Style.space(10)

      PText { text: "Calendars"; font.bold: true; font.pixelSize: Style.font.title }

      PText {
        visible: tab.sources.length === 0
        width: parent.width
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        tone: Qt.alpha(Color.popups.text, 0.6)
        text: "Add a calendar below. For Google Calendar, open Settings → your calendar → “Secret address in iCal format” and paste that link as an iCal link."
      }

      Repeater {
        model: tab.sources
        Item {
          id: r
          required property var modelData
          required property int index
          readonly property string sid: tab.store.sourceIds[index] || ""
          readonly property string err: tab.store.sourceError(index)
          readonly property bool off: modelData.enabled === false
          width: col.width
          height: Style.space(48)
          opacity: off ? 0.5 : 1

          Rectangle {
            id: swatch
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(14); height: width; radius: width / 2
            color: tab.store.colorOfSource(r.index)
            MouseArea {
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var names = Model.SOURCE_COLOR_NAMES
                var at = names.indexOf(r.modelData.colorName || "accent")
                tab.store.setSourceColor(r.index, names[(at + 1) % names.length])
              }
            }
          }
          Column {
            x: swatch.width + Style.space(10)
            width: r.width - x - actions.width - Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            PText { width: parent.width; text: Model.sourceTitle(r.modelData); font.bold: true }
            PText {
              width: parent.width
              text: r.err ? Model.errorText(r.err) : Model.KIND_LABELS[r.modelData.kind] + "  ·  " + Model.sourceDetail(r.modelData)
              font.pixelSize: Style.font.bodySmall
              tone: r.err ? Color.urgent : Qt.alpha(Color.popups.text, 0.55)
            }
          }
          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            ActionButton {
              icon: "pin"
              selected: tab.store.isVisible(r.sid)
              tooltip: "Show in agenda"
              onClicked: tab.store.toggleVisible(r.sid)
            }
            ActionButton {
              text: r.off ? "Off" : "On"
              onClicked: tab.store.toggleSource(r.index)
            }
            ActionButton { icon: "trash"; onClicked: tab.store.removeSource(r.index) }
          }
        }
      }

      Rectangle { width: parent.width; height: 1; color: Qt.alpha(Color.popups.text, 0.1) }

      PText { text: "Add a calendar"; font.bold: true }

      Flow {
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: Model.KINDS
          ActionButton {
            required property string modelData
            text: Model.KIND_LABELS[modelData]
            selected: tab.kind === modelData
            onClicked: { tab.kind = modelData; tab.formError = "" }
          }
        }
      }

      TextField {
        id: pathField
        visible: !tab.remote
        width: parent.width
        placeholderText: tab.kind === "file" ? "/path/to/calendar.ics" : "/path/to/folder of .ics files"
        onAccepted: tab.add()
      }
      TextField {
        id: urlField
        visible: tab.remote
        width: parent.width
        placeholderText: tab.kind === "caldav" ? "https://dav.example.com/" : "https://calendar.google.com/calendar/ical/…/basic.ics"
        onAccepted: tab.add()
      }
      Row {
        visible: tab.kind === "caldav"
        width: parent.width
        spacing: Style.space(8)
        TextField { id: userField; width: (parent.width - parent.spacing) / 2; placeholderText: "user name"; onAccepted: tab.add() }
        TextField { id: passField; width: (parent.width - parent.spacing) / 2; placeholderText: "app password"; password: true; onAccepted: tab.add() }
      }
      TextField {
        id: labelField
        width: parent.width
        placeholderText: "name (optional)"
        onAccepted: tab.add()
      }
      Toggle {
        visible: tab.remote
        width: parent.width
        label: "Allow local network"
        description: "For a server on your LAN or Tailscale. Public hosts never need this."
        foreground: Color.popups.text
        checked: tab.allowLocal
        onClicked: tab.allowLocal = !tab.allowLocal
      }

      Row {
        spacing: Style.space(8)
        ActionButton { text: tab.busy ? "Adding…" : "Add"; icon: "plus"; primary: true; enabled: !tab.busy; onClicked: tab.add() }
        PText {
          anchors.verticalCenter: parent.verticalCenter
          text: tab.formError || tab.notice
          tone: tab.formError ? Color.urgent : Color.accent
        }
      }

      Rectangle { width: parent.width; height: 1; color: Qt.alpha(Color.popups.text, 0.1) }

      Row {
        spacing: Style.space(8)
        PText { anchors.verticalCenter: parent.verticalCenter; text: "Refresh every" }
        ActionButton { icon: "left"; onClicked: tab.store.setCalendar({ calendarRefresh: Math.max(5, tab.store.calendar.calendarRefresh - 5) }) }
        PText { anchors.verticalCenter: parent.verticalCenter; text: tab.store.calendar.calendarRefresh + " min"; font.bold: true }
        ActionButton { icon: "right"; onClicked: tab.store.setCalendar({ calendarRefresh: Math.min(1440, tab.store.calendar.calendarRefresh + 5) }) }
      }

      Row {
        spacing: Style.space(8)
        ActionButton {
          text: "Import from Nookisle"
          onClicked: tab.store.importNookisle(function (ok, msg) { tab.notice = ok ? msg : ""; tab.formError = ok ? "" : msg })
        }
      }
      Item { width: 1; height: Style.space(8) }
    }
  }
}
