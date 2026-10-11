import QtQuick
import qs.Commons
import qs.Ui

// A city field that searches as you type. Matches drop down under the field;
// picking one stores the place's coordinates as well as its name, so the
// weather never lands on the wrong "Springfield". Enter takes the top match.
Item {
  id: picker

  required property var store
  property string current: ""
  property bool compact: false
  readonly property alias typing: field.activeFocus
  signal chosen(var place)
  signal cleared()

  property var results: []
  property bool searching: false
  property bool listOpen: false
  property int serial: 0
  property int highlight: 0           // the row Enter would pick
  property bool dirty: false          // the user has typed since the field got focus
  readonly property real rowH: Style.space(34)
  readonly property int shown: Math.min(results.length, 6)

  width: Style.space(280)
  height: field.implicitHeight
  z: listOpen ? 100 : 0

  property bool picking: false

  // A child's z only orders it among its siblings, so the rows laid out
  // after this one would paint over the dropdown. While it is open, lift
  // the containing items (a few levels up) above their siblings.
  property var lifted: []
  onListOpenChanged: {
    if (listOpen) {
      var p = picker.parent, n = 0
      while (p && n < 4) { lifted.push({ item: p, z: p.z }); p.z = 1000; p = p.parent; ++n }
    } else {
      for (var i = 0; i < lifted.length; ++i) lifted[i].item.z = lifted[i].z
      lifted = []
    }
  }
  Component.onDestruction: if (listOpen) { listOpen = false }
  function pick(place) {
    debounce.stop()
    picking = true
    listOpen = false
    field.text = place.label
    field.focus = false
    chosen(place)
    picking = false
  }
  // Move the highlight through the list like any dropdown (wraps at the ends).
  readonly property bool navigable: listOpen && shown > 0
  function move(delta) {
    if (shown === 0) return
    highlight = (highlight + delta + shown) % shown
  }
  function search() {
    var query = field.text.trim()
    if (query.length < 2) { results = []; searching = false; listOpen = false; return }
    var mine = ++serial
    searching = true
    listOpen = true
    store.helper("search-city", { query: query }, function (r) {
      if (mine !== picker.serial) return          // a newer search is in flight
      picker.searching = false
      picker.results = r && r.places ? r.places : []
      picker.highlight = 0
    }, 20)
  }

  onCurrentChanged: if (!field.activeFocus) field.text = current

  TextField {
    id: field
    width: parent.width
    text: picker.current
    placeholderText: "Search for a city"
    onTextEdited: { picker.dirty = true; debounce.restart() }
    onActiveFocusChanged: {
      if (activeFocus) {
        picker.dirty = false
        if (picker.results.length > 0 && text.trim().length >= 2) picker.listOpen = true
      } else {
        closeLater.restart()
        // Only a deliberate edit changes the setting: emptying the field
        // clears the city; typing without picking puts the old name back.
        if (picker.dirty && text.trim() === "" && picker.current !== "") picker.cleared()
        else if (picker.dirty && !picker.picking) text = picker.current
        picker.dirty = false
      }
    }
    onAccepted: {
      if (picker.results.length > 0 && !debounce.running) picker.pick(picker.results[Math.min(picker.highlight, picker.shown - 1)])
      else if (text.trim() === "") { picker.cleared(); picker.listOpen = false }
    }
    Keys.onDownPressed: function (event) { if (picker.navigable) { picker.move(1); event.accepted = true } else event.accepted = false }
    Keys.onUpPressed: function (event) { if (picker.navigable) { picker.move(-1); event.accepted = true } else event.accepted = false }
    Keys.onTabPressed: function (event) { if (picker.navigable) { picker.move((event.modifiers & Qt.ShiftModifier) ? -1 : 1); event.accepted = true } else event.accepted = false }
    Keys.onBacktabPressed: function (event) { if (picker.navigable) { picker.move(-1); event.accepted = true } else event.accepted = false }
    Keys.onEscapePressed: function (event) {
      if (picker.listOpen) { picker.listOpen = false; event.accepted = true } else event.accepted = false
    }
  }

  Timer { id: debounce; interval: 280; onTriggered: picker.search() }
  // Long enough for a click on a row to land before the list goes away.
  Timer { id: closeLater; interval: 180; onTriggered: picker.listOpen = false }

  Rectangle {
    id: dropdown
    visible: picker.listOpen
    y: field.height + Style.space(4)
    width: parent.width
    height: (picker.results.length > 0 ? picker.shown * picker.rowH : picker.rowH) + Style.space(8)
    radius: Style.space(10)
    // 85% opaque, whatever the bar's own alpha is.
    readonly property color solid: Qt.rgba(Color.bar.background.r, Color.bar.background.g, Color.bar.background.b, 1)
    color: Qt.alpha(Qt.tint(solid, Qt.alpha(Color.bar.text, 0.12)), 0.85)
    border.width: 1
    border.color: Qt.alpha(Color.bar.text, 0.16)
    opacity: picker.listOpen ? 1 : 0
    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    PText {
      visible: picker.results.length === 0
      anchors.centerIn: parent
      text: picker.searching ? "Searching…" : "No matches"
      tone: Qt.alpha(Color.popups.text, 0.6)
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(4)
      Repeater {
        model: picker.results.slice(0, 6)
        Rectangle {
          id: row
          required property var modelData
          required property int index
          width: parent.width
          height: picker.rowH
          radius: Style.space(7)
          color: index === picker.highlight ? Qt.alpha(Color.accent, 0.22) : "transparent"

          Row {
            anchors.verticalCenter: parent.verticalCenter
            x: Style.space(10)
            width: parent.width - Style.space(20)
            spacing: Style.space(8)
            PText {
              id: nm
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.name
              font.bold: true
              elide: Text.ElideNone
            }
            PText {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - nm.width - parent.spacing
              text: [row.modelData.region, row.modelData.country].filter(function (x) { return x }).join(", ")
              font.pixelSize: Style.font.bodySmall
              tone: Qt.alpha(Color.popups.text, 0.6)
            }
          }
          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: picker.highlight = row.index
            onClicked: picker.pick(row.modelData)
          }
        }
      }
    }
  }
}
