import QtQuick
import qs.Commons
import "../Model.js" as Model

// Month grid on the left, the selected day's events on the right.
Item {
  id: tab

  required property var store
  property bool typing: false
  signal gotoTab(string name)
  signal settingsRequested(string section)

  property date selected: store.now
  property int viewYear: selected.getFullYear()
  property int viewMonth: selected.getMonth()

  readonly property var rows: Model.itemsForDay(store.items, selected, store.calendar)
  // Range > 1 day: upcoming events from the selected day, grouped by day.
  readonly property int days: store.calendar.agendaDays || 1
  readonly property bool ranged: days > 1
  readonly property var groups: ranged ? Model.agendaGroups(store.items, selected, days, store.calendar) : []
  readonly property var flat: {
    var out = []
    for (var i = 0; i < groups.length; ++i) {
      out.push({ header: true, day: groups[i].day })
      for (var j = 0; j < groups[i].rows.length; ++j) out.push({ header: false, item: groups[i].rows[j] })
    }
    return out
  }
  readonly property int shownCount: ranged ? flat.filter(function (e) { return !e.header }).length : rows.length
  readonly property bool isToday: Model.sameDay(selected, store.now)
  // Web calendars for the accounts you are signed into, one button each.
  readonly property var webLinks: Model.webLinksFor(store.calendar.calendarSources)
  readonly property int errorCount: Object.keys(store.errors).length

  function pick(day) {
    selected = new Date(day.getFullYear(), day.getMonth(), day.getDate())
    viewYear = selected.getFullYear()
    viewMonth = selected.getMonth()
  }
  function stepMonth(n) {
    var d = new Date(viewYear, viewMonth + n, 1)
    viewYear = d.getFullYear()
    viewMonth = d.getMonth()
  }
  function handleMove(dx, dy) {
    if (dx) pick(Model.addDays(selected, dx))
    if (dy) pick(Model.addDays(selected, dy * 7))
  }
  function handleKey(t) {
    if (t === "[") stepMonth(-1)
    else if (t === "]") stepMonth(1)
    else if (t === "t" || t === "T") pick(store.now)
    else if (t === "r" || t === "R") store.sync()
    else return false
    return true
  }
  function scrollToNext() {
    if (ranged || !store.calendar.autoScrollToNextEvent || !isToday) return
    var at = Model.scrollTarget(rows, store.now)
    if (at >= 0) list.positionViewAtIndex(at, ListView.Beginning)
  }
  onRowsChanged: Qt.callLater(scrollToNext)
  onRangedChanged: Qt.callLater(scrollToNext)
  Component.onCompleted: Qt.callLater(scrollToNext)

  MonthGrid {
    id: grid
    store: tab.store
    width: Math.min(Style.space(290), tab.width * 0.5)
    viewYear: tab.viewYear
    viewMonth: tab.viewMonth
    selected: tab.selected
    onPicked: function (day) { tab.pick(day) }
    onStep: function (n) { tab.stepMonth(n) }
  }

  Rectangle {
    id: divider
    x: grid.width + Style.space(12)
    width: 1
    height: parent.height
    color: Qt.alpha(Color.popups.text, 0.1)
  }

  Item {
    id: side
    x: divider.x + Style.space(13)
    width: parent.width - x
    height: parent.height

    PText {
      id: dayTitle
      width: parent.width
      text: tab.ranged ? Model.agendaTitle(tab.days) : tab.isToday ? "Today" : Qt.formatDate(tab.selected, "dddd")
      font.pixelSize: Style.font.title
      font.bold: true
    }
    PText {
      id: daySub
      anchors.top: dayTitle.bottom
      width: parent.width
      text: (tab.ranged
        ? Qt.formatDate(tab.selected, "d MMM") + " \u2013 " + Qt.formatDate(Model.addDays(tab.selected, tab.days - 1), "d MMM")
        : Qt.formatDate(tab.selected, "d MMMM yyyy"))
        + (tab.shownCount ? "  \u00b7  " + tab.shownCount + (tab.shownCount === 1 ? " event" : " events") : "")
      font.pixelSize: Style.font.bodySmall
      tone: Qt.alpha(Color.popups.text, 0.6)
    }

    ListView {
      id: list
      anchors.top: daySub.bottom
      anchors.topMargin: Style.space(8)
      anchors.bottom: footer.top
      anchors.bottomMargin: Style.space(6)
      width: parent.width
      clip: true
      spacing: Style.space(2)
      model: tab.ranged ? tab.flat : tab.rows
      boundsBehavior: Flickable.StopAtBounds
      delegate: Item {
        id: entry
        required property var modelData
        readonly property bool header: tab.ranged && modelData.header === true
        width: list.width
        height: header ? head.implicitHeight + Style.space(10) : ev.implicitHeight

        PText {
          id: head
          visible: entry.header
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(2)
          width: parent.width
          text: entry.header ? (Model.sameDay(entry.modelData.day, tab.store.now) ? "Today" : Model.sameDay(entry.modelData.day, Model.addDays(tab.store.now, 1)) ? "Tomorrow" : Qt.formatDate(entry.modelData.day, "dddd d MMM")) : ""
          font.bold: true
          tone: Color.accent
        }
        EventRow {
          id: ev
          visible: !entry.header
          item: entry.header ? ({}) : (tab.ranged ? entry.modelData.item : entry.modelData)
          store: tab.store
          width: list.width
          fullTitle: tab.store.calendar.showFullEventTitles
        }
      }
    }

    Column {
      visible: tab.shownCount === 0
      anchors.centerIn: list
      width: list.width - Style.space(16)
      spacing: Style.space(10)
      PText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        elide: Text.ElideNone
        tone: Qt.alpha(Color.popups.text, 0.6)
        text: !tab.store.hasSources ? "No calendars yet." : tab.store.syncing ? "Syncing…" : tab.isToday ? "A quiet day. Nothing scheduled." : "Nothing on this day."
      }
      ActionButton {
        visible: !tab.store.hasSources
        anchors.horizontalCenter: parent.horizontalCenter
        primary: true
        icon: "plus"
        text: "Add a calendar in Settings"
        onClicked: tab.settingsRequested("calendars")
      }
    }

    Column {
      id: footer
      anchors.bottom: parent.bottom
      width: parent.width
      spacing: Style.space(6)

      // Open the real calendar, task list and mail in the default browser or
      // mail app: one button per page your signed-in accounts offer.
      Flow {
        id: linkRow
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: tab.webLinks
          ActionButton {
            required property var modelData
            icon: "open"
            text: modelData.name
            onClicked: tab.store.openUrl(modelData.url)
          }
        }
        ActionButton { icon: "mail"; text: "Mail"; onClicked: tab.store.openUrl("mailto:") }
      }

      Row {
        width: parent.width
        spacing: Style.space(6)
        PText {
          width: parent.width - refresh.width - parent.spacing
          anchors.verticalCenter: parent.verticalCenter
          font.pixelSize: Style.font.bodySmall
          tone: tab.errorCount > 0 ? Color.urgent : Qt.alpha(Color.popups.text, 0.5)
          text: !tab.store.hasSources ? "" : tab.store.syncing ? "Syncing\u2026"
            : tab.errorCount > 0 ? tab.errorCount + (tab.errorCount === 1 ? " calendar needs attention" : " calendars need attention")
            : tab.store.syncedAt ? "Synced " + tab.store.syncedAt.slice(11, 16) : ""
        }
        ActionButton {
          id: refresh
          icon: "refresh"
          enabled: !tab.store.syncing
          onClicked: tab.store.sync()
        }
      }
    }
  }
}
