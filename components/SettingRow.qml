import QtQuick
import qs.Commons

// A settings row: title and description on the left, the control (the
// default child) on the right.
Item {
  id: row

  property string label: ""
  property string description: ""
  default property alias control: slot.data

  width: parent ? parent.width : 0
  implicitHeight: Math.max(textCol.implicitHeight, slot.height) + Style.space(14)

  Column {
    id: textCol
    anchors.verticalCenter: parent.verticalCenter
    width: row.width - slot.width - Style.space(24)
    spacing: Style.space(2)
    PText { width: parent.width; text: row.label; font.bold: true }
    PText {
      width: parent.width
      visible: row.description !== ""
      text: row.description
      font.pixelSize: Style.font.bodySmall
      tone: Qt.alpha(Color.popups.text, 0.6)
      wrapMode: Text.Wrap
      elide: Text.ElideNone
    }
  }

  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }

  Rectangle {
    anchors.bottom: parent.bottom
    width: parent.width
    height: 1
    color: Qt.alpha(Color.popups.text, 0.07)
  }
}
