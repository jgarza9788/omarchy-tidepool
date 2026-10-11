import QtQuick
import qs.Commons

// Text in the popup palette. `tone` is the colour; the rest is plain Text.
Text {
  property color tone: Color.popups.text
  color: tone
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  textFormat: Text.PlainText
  renderType: Text.NativeRendering
  elide: Text.ElideRight
}
