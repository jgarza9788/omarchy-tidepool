import QtQuick
import qs.Commons

// The media apps that are running, one button each (a play icon marks the one
// that is playing). Clicking one makes the Media tab follow it and brings its
// window to the front. Shown with or without something playing, so you can
// always get to another app.
Row {
  id: row

  required property var store
  property var current: null          // the app the tab is showing
  signal picked(var player)

  visible: store.players.length > 0
  spacing: Style.space(6)

  PText {
    anchors.verticalCenter: parent.verticalCenter
    text: "App"
    font.pixelSize: Style.font.bodySmall
    tone: Qt.alpha(Color.popups.text, 0.55)
  }
  Repeater {
    model: row.store.players
    ActionButton {
      required property var modelData
      icon: modelData.isPlaying ? "play" : ""
      text: modelData.identity || "App"
      selected: modelData === row.current
      tooltip: "Switch to " + (modelData.identity || "this app")
      onClicked: row.picked(modelData)
    }
  }
}
