import QtQuick
import QtQuick.Shapes

// A tab silhouette: rounded top corners and a base that flares outward in
// concave quarter-circles, so it grows out of the surface it sits on (the
// "rounded tab" of https://css-tip.com/rounded-tab/). The item is
// flareLeft + bodyWidth + flareRight wide; the base is the bottom edge, or
// the top edge when `flipped`. Only the outline is stroked — never the base,
// so no seam shows where the tab meets the bar.
Item {
  id: tab

  property real bodyWidth: 200
  property real flareLeft: 12
  property real flareRight: 12
  property real radius: 12
  property color fillColor: "black"
  property color strokeColor: "transparent"
  property real strokeWidth: 1
  property bool flipped: false

  width: flareLeft + bodyWidth + flareRight

  readonly property real w: bodyWidth
  readonly property real h: height
  readonly property real fl: Math.max(0.001, flareLeft)
  readonly property real fr: Math.max(0.001, flareRight)
  readonly property real r: Math.max(0.001, Math.min(radius, bodyWidth / 2, height / 2))
  // Arc direction of the convex (top) corners; the flares turn the other way.
  readonly property int convex: flipped ? PathArc.Counterclockwise : PathArc.Clockwise
  readonly property int concave: flipped ? PathArc.Clockwise : PathArc.Counterclockwise
  function py(v) { return flipped ? height - v : v }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: -1
      fillColor: tab.fillColor
      startX: 0; startY: tab.py(tab.h)
      PathArc { x: tab.flareLeft; y: tab.py(tab.h - tab.fl); radiusX: tab.fl; radiusY: tab.fl; direction: tab.concave }
      PathLine { x: tab.flareLeft; y: tab.py(tab.r) }
      PathArc { x: tab.flareLeft + tab.r; y: tab.py(0); radiusX: tab.r; radiusY: tab.r; direction: tab.convex }
      PathLine { x: tab.flareLeft + tab.w - tab.r; y: tab.py(0) }
      PathArc { x: tab.flareLeft + tab.w; y: tab.py(tab.r); radiusX: tab.r; radiusY: tab.r; direction: tab.convex }
      PathLine { x: tab.flareLeft + tab.w; y: tab.py(tab.h - tab.fr) }
      PathArc { x: tab.flareLeft + tab.w + tab.flareRight; y: tab.py(tab.h); radiusX: tab.fr; radiusY: tab.fr; direction: tab.concave }
      PathLine { x: 0; y: tab.py(tab.h) }
    }

    ShapePath {
      strokeWidth: tab.strokeColor.a > 0 ? tab.strokeWidth : -1
      strokeColor: tab.strokeColor
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.RoundJoin
      startX: 0; startY: tab.py(tab.h)
      PathArc { x: tab.flareLeft; y: tab.py(tab.h - tab.fl); radiusX: tab.fl; radiusY: tab.fl; direction: tab.concave }
      PathLine { x: tab.flareLeft; y: tab.py(tab.r) }
      PathArc { x: tab.flareLeft + tab.r; y: tab.py(0); radiusX: tab.r; radiusY: tab.r; direction: tab.convex }
      PathLine { x: tab.flareLeft + tab.w - tab.r; y: tab.py(0) }
      PathArc { x: tab.flareLeft + tab.w; y: tab.py(tab.r); radiusX: tab.r; radiusY: tab.r; direction: tab.convex }
      PathLine { x: tab.flareLeft + tab.w; y: tab.py(tab.h - tab.fr) }
      PathArc { x: tab.flareLeft + tab.w + tab.flareRight; y: tab.py(tab.h); radiusX: tab.fr; radiusY: tab.fr; direction: tab.concave }
    }
  }
}
