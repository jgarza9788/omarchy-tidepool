import QtQuick
import qs.Commons
import "../Model.js" as Model

// One calendar entry: source-coloured bar, title, "09:00–10:00 · Room 4",
// and an optional label on the right ("12m", "now"). A call link gets a Join
// button; clicking the row opens its details (description, organizer,
// attendees, the link).
Item {
  id: row

  required property var item
  required property var store
  property string when: ""
  property bool fullTitle: false
  property bool expandable: true
  property bool expanded: false

  readonly property var span: Model.span(item)
  readonly property bool running: !!span && !item.allDay && span.from <= store.now && span.until > store.now
  readonly property bool past: !!span && !item.allDay && span.until <= store.now
  readonly property color tint: store.colorOfItem(item)
  readonly property string url: Model.safeUrl(item.meetingUrl)
  readonly property bool canJoin: url !== "" && !past
  readonly property string who: Model.attendeeSummary(item)
  readonly property bool hasDetails: !!(item.description || item.organizer || who || url)
  readonly property string detail: {
    var parts = [Model.timeLabel(item)]
    if (item.location && item.location !== url) parts.push(item.location)
    return parts.join("  ·  ")
  }

  width: parent ? parent.width : 0
  implicitHeight: Math.max(col.implicitHeight, Style.space(30)) + Style.space(4)
  Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

  // Click anywhere on the row for its details.
  MouseArea {
    anchors.fill: parent
    enabled: row.expandable && row.hasDetails
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: row.expanded = !row.expanded
  }

  Rectangle {
    id: mark
    x: 0
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(3)
    height: parent.height - Style.space(6)
    radius: width / 2
    color: row.tint
    opacity: row.past ? 0.35 : 1
  }

  Column {
    id: col
    x: mark.width + Style.space(8)
    y: Style.space(2)
    width: row.width - x - side.width - Style.space(8)
    spacing: Style.space(1)

    PText {
      width: parent.width
      text: row.item.title || "Untitled"
      font.bold: row.running
      elide: row.fullTitle || row.expanded ? Text.ElideNone : Text.ElideRight
      wrapMode: row.fullTitle || row.expanded ? Text.Wrap : Text.NoWrap
      tone: row.past ? Qt.alpha(Color.popups.text, 0.5) : Color.popups.text
    }
    PText {
      width: parent.width
      text: row.detail
      font.pixelSize: Style.font.bodySmall
      tone: Qt.alpha(Color.popups.text, 0.6)
    }

    // ── Details ──
    Column {
      width: parent.width
      visible: row.expanded
      spacing: Style.space(3)
      topPadding: Style.space(4)
      bottomPadding: Style.space(4)

      PText {
        visible: !!row.item.organizer
        width: parent.width
        text: "Organizer  " + row.item.organizer
        font.pixelSize: Style.font.bodySmall
        tone: Qt.alpha(Color.popups.text, 0.7)
      }
      PText {
        visible: row.who !== ""
        width: parent.width
        text: "With  " + row.who
        font.pixelSize: Style.font.bodySmall
        tone: Qt.alpha(Color.popups.text, 0.7)
      }
      PText {
        visible: !!row.item.description
        width: parent.width
        text: row.item.description || ""
        wrapMode: Text.Wrap
        maximumLineCount: 6
        elide: Text.ElideRight
        font.pixelSize: Style.font.bodySmall
        tone: Qt.alpha(Color.popups.text, 0.8)
      }
      PText {
        visible: row.url !== ""
        width: parent.width
        text: row.url
        font.pixelSize: Style.font.bodySmall
        tone: Qt.alpha(Color.accent, 0.9)
      }
    }
  }

  // Right side: Join, then the "12m" label.
  Row {
    id: side
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: Style.space(2)
    spacing: Style.space(8)

    ActionButton {
      visible: row.canJoin
      icon: "video"
      text: "Join"
      primary: row.running || (row.span && row.span.from.getTime() - row.store.now.getTime() < 15 * 60000)
      tabbable: false
      onClicked: row.store.openUrl(row.url)
    }
    PText {
      id: whenText
      visible: row.when !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: row.when
      font.bold: row.running
      tone: row.running ? Color.accent : Qt.alpha(Color.popups.text, 0.6)
    }
  }
}
