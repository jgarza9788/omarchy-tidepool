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
//   dots    a staggered grid of small dots, one column per band; the dots
//           grow and shrink with the sound, loud bands lighting more rows
//   wave    a smooth filled area under the spectrum
//   line    the same curve, stroked
//   fire    digital fire: square cells that flicker, in the accent and the
//           colours next to it on the wheel
Item {
  id: viz

  property bool active: false
  property string config: "cava.conf"          // a file in bin/
  property string styleName: "bars"
  property real gap: Style.space(3)
  property real minH: Style.space(3)
  property int bars: 40
  property var values: []
  property int tick: 0                      // counts cava frames; drives the fire's flicker
  property bool available: true

  readonly property bool barLike: styleName === "bars" || styleName === "mirror"
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
      onRead: function (line) { viz.values = Model.parseBars(line, viz.bars); viz.tick++ }
    }
    onExited: function (code) { if (viz.active && code === 127) viz.available = false }
  }

  // ── bars / mirror: one slot per band ──
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
      }
    }
  }

  // ── dots: a staggered grid, every other row shifted half a column ──
  Item {
    id: dotsView
    visible: viz.styleName === "dots"
    anchors.fill: parent
    readonly property var grid: Model.dotGrid(width, height, viz.bars)
    function band(i) { return viz.values.length > i ? viz.values[i] / 100 : 0 }

    Repeater {
      model: dotsView.visible ? dotsView.grid.rows * dotsView.grid.cols : 0
      Rectangle {
        id: dot
        required property int index
        readonly property int row: Math.floor(index / dotsView.grid.cols)
        readonly property int col: index % dotsView.grid.cols
        readonly property bool shifted: row % 2 === 1
        // A shifted row sits between two columns, so it follows both.
        readonly property real v: shifted ? (dotsView.band(col) + dotsView.band(col + 1)) / 2 : dotsView.band(col)
        // Same rule as Model.dotLevel / dotScale, inline: this runs for every dot every frame.
        readonly property real level: Math.max(0, Math.min(1, v * dotsView.grid.rows - row))
        readonly property real d: Math.max(1, dotsView.grid.size * (0.18 + 0.82 * level))

        visible: !shifted || col < dotsView.grid.cols - 1
        width: d
        height: d
        radius: d / 2
        x: (col + 0.5 + (shifted ? 0.5 : 0)) * dotsView.grid.pitchX - d / 2
        y: dotsView.height - (row + 0.5) * dotsView.grid.pitchY - d / 2
        color: Color.accent
        opacity: 0.3 + 0.7 * level
      }
    }
  }

  // ── fire: square cells that flicker, tinted from the accent's neighbours ──
  Item {
    id: fireView
    visible: viz.styleName === "fire"
    anchors.fill: parent
    readonly property var grid: Model.cellGrid(width, height, viz.bars)
    readonly property real hue: Color.accent.hslHue
    readonly property real sat: Color.accent.hslSaturation
    readonly property real lig: Color.accent.hslLightness

    // Flame height (in rows) per column: the band blended with its neighbours
    // so tongues are wider than one cell, licked up and down by noise.
    readonly property var heights: {
      var out = [], n = viz.bars, v = viz.values, g = grid
      if (!visible) return out
      for (var c = 0; c < n; ++c) {
        var a = (v.length > c ? v[c] : 0) / 100
        var l = (c > 0 && v.length > c - 1 ? v[c - 1] : 0) / 100
        var r = (v.length > c + 1 ? v[c + 1] : 0) / 100
        out.push(Model.fireHeight(0.6 * a + 0.2 * (l + r), g.rows, Model.noise(c, 99, viz.tick >> 1)))
      }
      return out
    }

    Repeater {
      model: fireView.visible ? fireView.grid.cols * fireView.grid.rows : 0
      Rectangle {
        required property int index
        readonly property int col: index % fireView.grid.cols
        readonly property int row: Math.floor(index / fireView.grid.cols)
        readonly property real state: Model.fireState(fireView.heights.length > col ? fireView.heights[col] : 0, row, Model.noise(col, row, viz.tick))
        readonly property var hsl: Model.fireHsl(state, fireView.hue, fireView.sat, fireView.lig)

        width: fireView.grid.size
        height: fireView.grid.size
        x: col * fireView.grid.pitch + (fireView.grid.pitch - width) / 2
        y: viz.height - (row + 1) * fireView.grid.pitch + (fireView.grid.pitch - height) / 2
        radius: Math.min(1, width / 4)
        // lit: the fire colour; dark: a barely-there cell so the grid shows.
        color: state >= 0 ? Qt.hsla(hsl[0], hsl[1], hsl[2], hsl[3]) : Qt.alpha(Color.accent, 0.06)
        // every other row a little dimmer: scanlines
        opacity: row % 2 === 1 ? 0.86 : 1
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
