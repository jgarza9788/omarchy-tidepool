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
  property string config: "cava.conf"          // a file in bin/
  property real gap: Style.space(3)
  property real minH: Style.space(3)
  property int bars: 40
  property var values: []
  property bool available: true

  visible: available
  implicitHeight: Style.space(110)

  onActiveChanged: if (!active) values = []

  Process {
    id: cava
    command: ["cava", "-p", Qt.resolvedUrl("../bin/" + viz.config).toString().replace(/^file:\/\//, "")]
    running: viz.active
    stdout: SplitParser {
      onRead: function (line) { viz.values = Model.parseBars(line, viz.bars) }
    }
    onExited: function (code) { if (viz.active && code === 127) viz.available = false }
  }

  Row {
    anchors.fill: parent
    spacing: viz.gap
    Repeater {
      model: viz.bars
      Item {
        required property int index
        readonly property real v: viz.values.length > index ? viz.values[index] / 100 : 0
        width: (viz.width - (viz.bars - 1) * viz.gap) / viz.bars
        height: viz.height

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(viz.minH, parent.height * parent.v)
          radius: Math.min(width / 2, Math.max(1, viz.gap))
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
