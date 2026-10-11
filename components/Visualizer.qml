import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import "../Model.js" as Model

// Spectrum from cava (config in bin/cava*.conf). cava only runs while
// `active`, so this costs nothing when closed or paused. If cava is not
// installed the item hides itself.
//
// `styleName` picks how it is drawn (see Model.VIZ_STYLES):
//   bars    upward rounded bars
//   mirror  bars growing up and down from a centre line
//   dots    one dot per band, at the band's level
//   wave    a smooth filled area under the spectrum
//   line    the same curve, stroked
Item {
  id: viz

  property bool active: false
  property string config: "cava.conf"          // a file in bin/
  property string styleName: "bars"
  property real gap: Style.space(3)
  property real minH: Style.space(3)
  property int bars: 40
  property var values: []
  property bool available: true

  readonly property bool barLike: styleName === "bars" || styleName === "mirror" || styleName === "dots"
  readonly property real slotW: (width - (bars - 1) * gap) / bars
  readonly property real stroke: Math.max(1, Math.min(Style.space(2), height / 6))

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

  // ── bars / mirror / dots: one slot per band ──
  Row {
    visible: viz.barLike
    anchors.fill: parent
    spacing: viz.gap
    Repeater {
      model: viz.barLike ? viz.bars : 0
      Item {
        id: slot
        required property int index
        readonly property real v: viz.values.length > index ? viz.values[index] / 100 : 0
        readonly property real dot: Math.max(Style.space(2), Math.min(viz.slotW * 0.8, Style.space(8)))
        width: viz.slotW
        height: viz.height

        // bars: grow up from the bottom
        Rectangle {
          visible: viz.styleName === "bars"
          anchors.bottom: parent.bottom
          width: parent.width
          height: Math.max(viz.minH, parent.height * slot.v)
          radius: Math.min(width / 2, Math.max(1, viz.gap))
          gradient: Gradient {
            GradientStop { position: 0.0; color: Color.accent }
            GradientStop { position: 1.0; color: Qt.alpha(Color.accent, 0.25) }
          }
          opacity: 0.35 + 0.65 * slot.v
          Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
        }

        // mirror: grow both ways from the middle
        Rectangle {
          visible: viz.styleName === "mirror"
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: Math.max(viz.minH, parent.height * slot.v)
          radius: Math.min(width / 2, Math.max(1, viz.gap))
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.alpha(Color.accent, 0.35) }
            GradientStop { position: 0.5; color: Color.accent }
            GradientStop { position: 1.0; color: Qt.alpha(Color.accent, 0.35) }
          }
          opacity: 0.4 + 0.6 * slot.v
          Behavior on height { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
        }

        // dots: a dot riding at the band's level
        Rectangle {
          visible: viz.styleName === "dots"
          x: (parent.width - slot.dot) / 2
          y: (parent.height - slot.dot) * (1 - slot.v)
          width: slot.dot
          height: slot.dot
          radius: width / 2
          color: Color.accent
          opacity: 0.35 + 0.65 * slot.v
          Behavior on y { NumberAnimation { duration: 70; easing.type: Easing.OutQuad } }
        }
      }
    }
  }

  // ── wave / line: one smooth curve through all the bands ──
  Item {
    visible: !viz.barLike
    anchors.fill: parent
    anchors.topMargin: viz.stroke
    anchors.bottomMargin: viz.stroke

    Shape {
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer

      // wave: filled area + a thin edge
      ShapePath {
        id: area
        strokeWidth: viz.styleName === "wave" ? viz.stroke : -1
        strokeColor: Color.accent
        joinStyle: ShapePath.RoundJoin
        fillGradient: LinearGradient {
          x1: 0; y1: 0; x2: 0; y2: area.height
          GradientStop { position: 0.0; color: Qt.alpha(Color.accent, 0.55) }
          GradientStop { position: 1.0; color: Qt.alpha(Color.accent, 0.05) }
        }
        property real height: viz.height - viz.stroke * 2
        PathSvg { path: viz.styleName === "wave" ? Model.wavePath(viz.values, viz.width, viz.height - viz.stroke * 2, true) : "" }
      }

      // line: the curve only
      ShapePath {
        strokeWidth: viz.styleName === "line" ? viz.stroke : -1
        strokeColor: Color.accent
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: viz.styleName === "line" ? Model.wavePath(viz.values, viz.width, viz.height - viz.stroke * 2, false) : "" }
      }
    }
  }
}
