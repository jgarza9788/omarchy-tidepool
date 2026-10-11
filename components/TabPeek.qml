import QtQuick
import Quickshell
import qs.Commons

// The hover peek: a small tab that grows out of the bar above the widget, in
// the bar's own colour. Same flare and rise as the panel, no focus grab, so
// the pointer can pass between the widget and the card.
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property bool open: false
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property int padding: Style.space(12)
  readonly property real flare: Style.space(14)
  readonly property bool containsMouse: hover.hovered
  readonly property bool top: bar && bar.position === "top"
  property real progress: open ? 1 : 0
  Behavior on progress {
    NumberAnimation { duration: root.open ? 220 : 140; easing.type: root.open ? Easing.OutCubic : Easing.InCubic }
  }

  default property alias contentItem: holder.data

  visible: open || progress > 0
  color: "transparent"
  implicitWidth: contentWidth + flare * 2
  implicitHeight: contentHeight + 1

  anchor {
    id: popupAnchor
    window: root.anchorItem ? root.anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      var win = root.anchorItem ? root.anchorItem.QsWindow.window : null
      if (!win) return
      var p = win.contentItem.mapFromItem(root.anchorItem, root.anchorItem.width / 2 - root.implicitWidth / 2, 0)
      var x = Math.max(0, Math.min(p.x, win.width - root.implicitWidth))
      // Flush with the bar: above it for a bottom bar, below it for a top bar.
      popupAnchor.rect.x = Math.round(x)
      popupAnchor.rect.y = Math.round(root.top ? win.height - 1 : -root.implicitHeight + 1)
    }
  }

  Item {
    anchors.fill: parent
    clip: true

    Item {
      width: parent.width
      height: root.contentHeight
      y: (root.top ? -1 : 1) * (1 - root.progress) * Math.min(root.contentHeight, Style.space(36)) + (root.top ? 1 : 0)
      opacity: Math.min(1, root.progress * 1.6)

      TabShape {
        anchors.fill: parent
        bodyWidth: root.contentWidth
        flareLeft: root.flare
        flareRight: root.flare
        radius: Style.space(14)
        flipped: root.top
        fillColor: Color.bar.background
        strokeColor: Qt.alpha(Color.bar.text, 0.14)
      }
      Item {
        id: holder
        x: root.flare + root.padding
        y: root.padding
        width: root.contentWidth - root.padding * 2
        height: root.contentHeight - root.padding * 2
      }
      HoverHandler { id: hover }
    }
  }
}
