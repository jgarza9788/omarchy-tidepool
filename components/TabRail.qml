import QtQuick
import qs.Commons
import "../Model.js" as Model

// Browser-style tabs. One tab-shaped blob slides between the labels (so the
// switch is a single fluid motion) and merges into the card below through
// concave flares, as in https://css-tip.com/rounded-tab/. The first tab sits
// flush with the card's left edge, so its left flare folds away.
Item {
  id: rail

  property var tabs: []
  property string current: ""
  property var badges: ({})
  property color cardColor: Color.bar.background
  property bool reduceMotion: false
  readonly property real tabH: Style.space(36)
  readonly property real flare: Style.space(12)
  readonly property real padX: Style.space(12)
  readonly property int currentIndex: {
    for (var i = 0; i < tabs.length; ++i) if (tabs[i].id === current) return i
    return 0
  }
  readonly property bool firstActive: currentIndex === 0

  signal picked(string id)
  signal settingsRequested()

  implicitHeight: tabH

  // Body (without flares) of the active tab, read from the laid-out labels.
  property int built: 0
  readonly property Item activeItem: { built; return reps.itemAt(currentIndex) }
  readonly property real wantLeft: activeItem ? activeItem.x + (firstActive ? 0 : flare) : 0
  readonly property real wantRight: activeItem ? activeItem.x + activeItem.width - flare : 0
  property real bodyLeft: wantLeft
  property real bodyRight: wantRight
  property real flareLeft: firstActive ? 0 : flare
  // Springs, not fixed-time eases: a second click mid-slide re-aims the blob
  // from where it is, keeping its speed, instead of restarting a curve.
  Behavior on bodyLeft { enabled: !rail.reduceMotion; SpringAnimation { spring: 3.2; damping: 0.42; epsilon: 0.25 } }
  Behavior on bodyRight { enabled: !rail.reduceMotion; SpringAnimation { spring: 3.2; damping: 0.42; epsilon: 0.25 } }
  Behavior on flareLeft { enabled: !rail.reduceMotion; SpringAnimation { spring: 3.2; damping: 0.42; epsilon: 0.25 } }

  TabShape {
    x: rail.bodyLeft - rail.flareLeft
    y: 0
    height: rail.tabH + 1                 // 1px under the card so no seam shows
    bodyWidth: Math.max(1, rail.bodyRight - rail.bodyLeft)
    flareLeft: rail.flareLeft
    flareRight: rail.flare
    radius: Style.space(12)
    fillColor: rail.cardColor
  }

  Row {
    id: row
    Repeater {
      id: reps
      model: rail.tabs
      onItemAdded: rail.built++
      Item {
        id: t
        required property var modelData
        required property int index
        readonly property bool active: rail.current === modelData.id
        width: label.implicitWidth + rail.padX * 2 + (index === 0 ? rail.flare : rail.flare * 2)
        height: rail.tabH

        // Keyboard: Tab reaches each tab, Enter / Space picks it.
        activeFocusOnTab: true
        Keys.onReturnPressed: rail.picked(t.modelData.id)
        Keys.onEnterPressed: rail.picked(t.modelData.id)
        Keys.onSpacePressed: rail.picked(t.modelData.id)
        Accessible.role: Accessible.PageTab
        Accessible.name: t.modelData.label
        Accessible.description: rail.badges[t.modelData.id] ? "Active" : ""
        Accessible.focusable: true
        Accessible.focused: t.activeFocus
        Accessible.selected: t.active
        Accessible.onPressAction: rail.picked(t.modelData.id)

        // Hover wash on inactive tabs; it answers the press at once, and a ring shows keyboard focus.
        Rectangle {
          x: index === 0 ? 0 : rail.flare
          y: Style.space(4)
          width: parent.width - rail.flare - x
          height: parent.height - Style.space(8)
          radius: Style.space(8)
          color: Qt.alpha(Color.bar.text, mouse.pressed ? 0.13 : 0.07)
          border.width: t.activeFocus ? 1 : 0
          border.color: Color.accent
          opacity: t.activeFocus || (!t.active && mouse.containsMouse) ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: mouse.pressed ? 0 : 140 } }
        }

        Row {
          id: label
          x: (index === 0 ? 0 : rail.flare) + rail.padX
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)
          PText {
            anchors.verticalCenter: parent.verticalCenter
            text: Model.glyph(t.modelData.icon)
            font.pixelSize: Style.font.subtitle
            tone: t.active ? Color.accent : Qt.alpha(Color.bar.text, mouse.containsMouse ? 0.95 : 0.65)
            Behavior on tone { ColorAnimation { duration: 160 } }
          }
          PText {
            anchors.verticalCenter: parent.verticalCenter
            text: t.modelData.label
            font.bold: t.active
            elide: Text.ElideNone
            tone: t.active ? Color.bar.text : Qt.alpha(Color.bar.text, mouse.containsMouse ? 0.95 : 0.65)
            Behavior on tone { ColorAnimation { duration: 160 } }
          }
        }

        Rectangle {
          visible: !!rail.badges[t.modelData.id]
          x: label.x + label.width + Style.space(2)
          y: Style.space(9)
          width: Style.space(5); height: width; radius: width / 2
          color: Color.accent
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: rail.picked(t.modelData.id)
        }
      }
    }
  }

  // A button, not a tab: opens the settings app.
  Item {
    id: gear
    x: row.width + Style.space(10)
    width: gearRow.implicitWidth + Style.space(20)
    height: rail.tabH
    readonly property bool hot: gearMouse.containsMouse
    activeFocusOnTab: true
    Keys.onReturnPressed: rail.settingsRequested()
    Keys.onEnterPressed: rail.settingsRequested()
    Keys.onSpacePressed: rail.settingsRequested()
    Accessible.role: Accessible.Button
    Accessible.name: "Settings"
    Accessible.focusable: true
    Accessible.focused: gear.activeFocus
    Accessible.onPressAction: rail.settingsRequested()

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: rail.tabH - Style.space(8)
      radius: Style.space(8)
      color: Qt.alpha(Color.bar.text, gearMouse.pressed ? 0.16 : gear.hot ? 0.1 : 0.05)
      border.width: gear.activeFocus ? 1 : 0
      border.color: Color.accent
      Behavior on color { enabled: !gearMouse.pressed; ColorAnimation { duration: 140 } }
    }
    Row {
      id: gearRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      PText {
        anchors.verticalCenter: parent.verticalCenter
        text: Model.glyph("cog")
        font.pixelSize: Style.font.subtitle
        tone: gear.hot || gear.activeFocus ? Color.accent : Qt.alpha(Color.bar.text, 0.8)
        Behavior on tone { ColorAnimation { duration: 160 } }
      }
      PText {
        anchors.verticalCenter: parent.verticalCenter
        text: "Settings"
        elide: Text.ElideNone
        tone: Qt.alpha(Color.bar.text, gear.hot ? 1 : 0.8)
      }
    }
    MouseArea {
      id: gearMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rail.settingsRequested()
    }
  }
}
