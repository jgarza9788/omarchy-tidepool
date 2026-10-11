import QtQuick
import qs.Commons
import "../Model.js" as Model

// Flat button in the popup palette: optional glyph (by Model.GLYPH name) and
// text. `selected` paints the theme's selected fill; `primary` the accent.
Rectangle {
  id: b

  property string text: ""
  property string icon: ""
  property bool selected: false
  property bool primary: false
  property bool enabled: true
  property bool leftAlign: false
  property bool tabbable: true
  property string tooltip: ""
  readonly property bool hot: mouse.containsMouse

  signal clicked()

  implicitWidth: row.implicitWidth + Style.space(20)
  implicitHeight: Style.space(28)
  radius: Style.cornerRadius
  opacity: enabled ? 1 : 0.4
  color: !enabled ? "transparent"
    : mouse.pressed ? Style.pressedFill
    : primary ? Qt.alpha(Color.accent, hot ? 0.35 : 0.22)
    : hot || activeFocus ? Style.hoverFill
    : selected ? Style.selectedFill
    : "transparent"
  // Keyboard: Tab reaches the button, Enter / Space press it, a ring shows where it is.
  activeFocusOnTab: tabbable && enabled && visible
  Keys.onReturnPressed: if (enabled) b.clicked()
  Keys.onEnterPressed: if (enabled) b.clicked()
  Keys.onSpacePressed: if (enabled) b.clicked()
  border.width: primary || activeFocus ? 1 : 0
  border.color: activeFocus ? Color.accent : Qt.alpha(Color.accent, 0.6)
  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    x: b.leftAlign ? Style.space(12) : Math.round((b.width - width) / 2)
    spacing: Style.space(6)
    PText {
      visible: b.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: Model.glyph(b.icon)
      tone: b.primary || b.selected ? Color.accent : Color.popups.text
      font.pixelSize: Style.font.subtitle
    }
    PText {
      visible: b.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: b.text
      font.bold: b.selected
      tone: b.primary || b.selected ? Color.accent : Color.popups.text
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: b.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: b.clicked()
  }
}
