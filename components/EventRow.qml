import QtQuick
import qs.Commons
import "../Model.js" as Model

// One calendar entry: source-coloured bar, title, "09:00–10:00 · Room 4",
// and an optional label on the right ("12m", "now").
Item {
  id: row

  required property var item
  required property var store
  property string when: ""
  property bool fullTitle: false

  readonly property var span: Model.span(item)
  readonly property bool running: !!span && !item.allDay && span.from <= store.now && span.until > store.now
  readonly property bool past: !!span && !item.allDay && span.until <= store.now
  readonly property color tint: store.colorOfItem(item)
  readonly property string detail: {
    var parts = [Model.timeLabel(item)]
    if (item.location) parts.push(item.location)
    return parts.join("  ·  ")
  }

  width: parent ? parent.width : 0
  implicitHeight: Math.max(col.implicitHeight, Style.space(30)) + Style.space(4)

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
    anchors.verticalCenter: parent.verticalCenter
    width: row.width - x - (whenText.visible ? whenText.width + Style.space(8) : 0)
    spacing: Style.space(1)

    PText {
      width: parent.width
      text: row.item.title || "Untitled"
      font.bold: row.running
      elide: row.fullTitle ? Text.ElideNone : Text.ElideRight
      wrapMode: row.fullTitle ? Text.Wrap : Text.NoWrap
      tone: row.past ? Qt.alpha(Color.popups.text, 0.5) : Color.popups.text
    }
    PText {
      width: parent.width
      text: row.detail
      font.pixelSize: Style.font.bodySmall
      tone: Qt.alpha(Color.popups.text, 0.6)
    }
  }

  PText {
    id: whenText
    visible: row.when !== ""
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: row.when
    font.bold: row.running
    tone: row.running ? Color.accent : Qt.alpha(Color.popups.text, 0.6)
  }
}
