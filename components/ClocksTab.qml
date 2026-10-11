import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

// World clocks. The zones are chosen in the settings app; this tab shows
// them and lets you drop one.
Item {
  id: tab

  required property var store
  property var host: null
  property bool typing: false
  signal gotoTab(string name)
  signal settingsRequested(string section)

  readonly property var zones: store.cfg.worldClocks

  function handleMove(dx, dy) {}
  function handleKey(t) { return false }

  function removeZone(zone) {
    if (host) host.persist({ worldClocks: zones.filter(function (z) { return z !== zone }).join(", ") })
  }

  Flickable {
    anchors.fill: parent
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: parent.width
      spacing: Style.space(14)

      // ── World clocks ──
      PText { text: "World clocks"; font.bold: true; font.pixelSize: Style.font.title }

      Repeater {
        model: tab.zones
        Item {
          id: z
          required property string modelData
          readonly property var info: tab.store.zoneOffsets[modelData]
          readonly property bool ok: !!info && info.offsetMin !== undefined
          readonly property date wall: ok ? Model.zoneWall(tab.store.nowMs, info.offsetMin) : tab.store.now
          width: col.width
          height: Style.space(32)

          PText {
            width: parent.width * 0.4
            anchors.verticalCenter: parent.verticalCenter
            text: Model.zoneCity(z.modelData)
            font.bold: true
          }
          PText {
            x: parent.width * 0.4
            width: parent.width * 0.22
            anchors.verticalCenter: parent.verticalCenter
            text: z.ok ? Qt.formatTime(z.wall, "HH:mm") : "?"
            font.pixelSize: Style.font.title
            tone: Color.accent
          }
          PText {
            x: parent.width * 0.62
            width: parent.width * 0.28
            anchors.verticalCenter: parent.verticalCenter
            text: z.ok ? (Model.sameDay(z.wall, tab.store.now) ? "" : (z.wall > tab.store.now ? "tmrw " : "yday ")) + Model.offsetFromLocal(z.info.offsetMin, tab.store.localOffsetMin) : "unknown zone"
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.6)
          }
          ActionButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            icon: "close"
            onClicked: tab.removeZone(z.modelData)
          }
        }
      }

      PText {
        visible: tab.zones.length === 0
        text: "No world clocks yet."
        tone: Qt.alpha(Color.popups.text, 0.55)
      }

      ActionButton {
        icon: tab.zones.length === 0 ? "plus" : "cog"
        primary: tab.zones.length === 0
        text: tab.zones.length === 0 ? "Add time zones in Settings" : "Edit time zones in Settings"
        onClicked: tab.settingsRequested("clocks")
      }
    }
  }
}
