import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "../Model.js" as Model

// Spectrum bars from cava (config in bin/cava.conf). cava only runs while
// `active`, so the tab costs nothing when closed or paused. If cava is not
// installed the item hides itself.
Item {
  id: viz

  property bool active: false
  property int bars: 40
  property var values: []
  property bool available: true
  readonly property real minH: Style.space(3)

  visible: available
  implicitHeight: Style.space(110)

  onActiveChanged: if (!active) values = []

  Process {
    id: cava
    command: ["cava", "-p", Qt.resolvedUrl("../bin/cava.conf").toString().replace(/^file:\/\//, "")]
    running: viz.active
    stdout: SplitParser {
      onRead: function (line) { viz.values = Model.parseBars(line, viz.bars) }
    }
    onExited: function (code) { if (viz.active && code === 127) viz.available = false }
  }

  Row {
    anchors.fill: parent
    spacing: Style.space(3)
    Repeater {
      model: viz.bars
      Item {
        required property int index
        readonly property real v: viz.values.length > index ? viz.values[index] / 100 : 0
        width: (viz.width - (viz.bars - 1) * Style.space(3)) / viz.bars
        height: viz.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(viz.minH, parent.height * parent.v)
          radius: Math.min(width / 2, Style.space(3))
          gradient: Gradient {
            GradientStop { position: 0.0; color: Color.accent }
            GradientStop { position: 1.0; color: Qt.alpha(Color.accent, 0.25) }
          }
          opacity: 0.35 + 0.65 * parent.v
          Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
        }
      }
    }
  }
}
