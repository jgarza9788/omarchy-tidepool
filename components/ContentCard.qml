import QtQuick
import QtQuick.Shapes

// The card under the tab rail: a rounded rectangle whose top-left corner can
// square off (animated) when the first tab sits flush with it.
Item {
  id: card

  property color fillColor: "black"
  property real radius: 12
  property real topLeftRadius: radius

  readonly property real tl: Math.max(0.001, Math.min(topLeftRadius, width / 2, height / 2))
  readonly property real rr: Math.max(0.001, Math.min(radius, width / 2, height / 2))

  Behavior on topLeftRadius { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      fillColor: card.fillColor
      startX: 0; startY: card.tl
      PathArc { x: card.tl; y: 0; radiusX: card.tl; radiusY: card.tl; direction: PathArc.Clockwise }
      PathLine { x: card.width - card.rr; y: 0 }
      PathArc { x: card.width; y: card.rr; radiusX: card.rr; radiusY: card.rr; direction: PathArc.Clockwise }
      PathLine { x: card.width; y: card.height - card.rr }
      PathArc { x: card.width - card.rr; y: card.height; radiusX: card.rr; radiusY: card.rr; direction: PathArc.Clockwise }
      PathLine { x: card.rr; y: card.height }
      PathArc { x: 0; y: card.height - card.rr; radiusX: card.rr; radiusY: card.rr; direction: PathArc.Clockwise }
      PathLine { x: 0; y: card.tl }
    }
  }
}
