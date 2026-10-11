import QtQuick
import Quickshell.Services.Mpris
import qs.Commons
import "../Model.js" as Model

// Media: whatever is playing, through MPRIS (music, video, podcasts, a browser tab). Controls act on the player the store picked
// (the one playing, else the first).
Item {
  id: tab

  required property var store
  property var host: null
  property bool typing: false
  signal gotoTab(string name)
  signal closeRequested()

  readonly property var p: store.player
  readonly property bool has: store.hasPlayer
  // The player's art URL, ignoring the empty "file:///" some players report when a track has none.
  readonly property string art: p && p.trackArtUrl && !/\/$/.test(String(p.trackArtUrl)) ? String(p.trackArtUrl) : ""
  readonly property real length: p && p.lengthSupported ? p.length : 0
  readonly property real position: p && p.positionSupported ? p.position : 0

  function handleMove(dx, dy) {}
  function handleKey(t) {
    if (t === " ") { if (p && p.canTogglePlaying) p.togglePlaying(); return true }
    if (t === "n") { if (p && p.canGoNext) p.next(); return true }
    if (t === "p") { if (p && p.canGoPrevious) p.previous(); return true }
    if (t === "s") { toggleShuffle(); return true }
    if (t === "v") { stepVisualizer(1); return true }
    if (t === "V") { stepVisualizer(-1); return true }
    if (t === "r") { cycleRepeat(); return true }
    if (t === "+" || t === "=") { nudgeVolume(0.05); return true }
    if (t === "-") { nudgeVolume(-0.05); return true }
    return false
  }

  // ── Controls (each only when the player supports it) ──
  readonly property bool canSeekNow: !!p && p.canSeek && length > 0
  readonly property bool shuffleOk: !!p && p.shuffleSupported
  readonly property bool loopOk: !!p && p.loopSupported
  readonly property bool volumeOk: !!p && p.volumeSupported
  readonly property string loopName: !p ? "None" : (p.loopState === MprisLoopState.Track ? "Track" : p.loopState === MprisLoopState.Playlist ? "Playlist" : "None")
  property real lastVolume: 0.7

  // Visualizer style: step to the previous / next and keep the choice.
  readonly property string vizStyle: store.cfg.visualizerStyle
  function stepVisualizer(delta) { if (host) host.persist({ visualizerStyle: Model.vizStep(vizStyle, delta) }) }

  // Follow an app and bring its window up front (the panel gets out of the way).
  function pickApp(player) {
    store.preferredId = store.playerId(player)
    store.focusApp(player)
    closeRequested()
  }

  function toggleShuffle() { if (shuffleOk) p.shuffle = !p.shuffle }
  function cycleRepeat() {
    if (!loopOk) return
    var next = Model.loopNext(loopName)
    p.loopState = next === "Track" ? MprisLoopState.Track : next === "Playlist" ? MprisLoopState.Playlist : MprisLoopState.None
  }
  function setVolume(v) { if (volumeOk) p.volume = Math.max(0, Math.min(1, v)) }
  function nudgeVolume(d) { if (volumeOk) setVolume(p.volume + d) }
  function toggleMute() {
    if (!volumeOk) return
    if (p.volume > 0.001) { lastVolume = p.volume; setVolume(0) } else setVolume(lastVolume)
  }
  property real seekPreview: -1       // while dragging the seek bar, 0..1

  // MPRIS does not push position changes; ask while visible and playing.
  Timer {
    interval: 1000
    repeat: true
    running: tab.visible && tab.has && tab.store.playing
    onTriggered: if (tab.p) tab.p.positionChanged()
  }

  function mmss(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
  }

  Column {
    visible: tab.has
    anchors.fill: parent
    spacing: Style.space(14)

    Row {
      width: parent.width
      spacing: Style.space(20)

      Rectangle {
        id: art
        width: Style.space(200); height: width
        radius: Style.cornerRadius
        color: Qt.alpha(Color.popups.text, 0.07)
        clip: true
        Image {
          anchors.fill: parent
          source: tab.art
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: status === Image.Ready
        }
        PText {
          anchors.centerIn: parent
          visible: tab.art === ""
          text: Model.glyph("media")
          font.pixelSize: Style.space(64)
          tone: Qt.alpha(Color.accent, 0.6)
        }
      }

      Column {
        width: parent.width - art.width - parent.spacing
        spacing: Style.space(8)

        PText {
          width: parent.width
          text: tab.p ? (tab.p.trackTitle || "Unknown title") : ""
          font.pixelSize: Style.font.display
          font.bold: true
        }
        PText {
          width: parent.width
          text: tab.p ? [tab.p.trackArtist, tab.p.trackAlbum].filter(function (x) { return !!x }).join("  \u00b7  ") : ""
          font.pixelSize: Style.font.title
          tone: Color.accent
        }

        Item { width: 1; height: Style.space(6) }

        // Seek bar: click or drag to jump.
        Item {
          id: seek
          width: parent.width
          height: Style.space(16)
          visible: tab.length > 0
          readonly property real frac: tab.seekPreview >= 0 ? tab.seekPreview : Math.max(0, Math.min(1, tab.position / Math.max(1, tab.length)))

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: Style.space(5)
            radius: height / 2
            color: Qt.alpha(Color.popups.text, 0.12)
            Rectangle {
              width: parent.width * seek.frac
              height: parent.height
              radius: height / 2
              color: Color.accent
            }
          }
          Rectangle {
            visible: tab.canSeekNow
            x: seek.width * seek.frac - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(12); height: width; radius: width / 2
            color: Color.accent
            scale: seekMouse.pressed || seekMouse.containsMouse ? 1.25 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
          }
          MouseArea {
            id: seekMouse
            anchors.fill: parent
            enabled: tab.canSeekNow
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            function fracAt(x) { return Math.max(0, Math.min(1, x / width)) }
            onPressed: function (m) { tab.seekPreview = fracAt(m.x) }
            onPositionChanged: function (m) { if (pressed) tab.seekPreview = fracAt(m.x) }
            onReleased: {
              if (tab.seekPreview >= 0 && tab.p) tab.p.position = tab.seekPreview * tab.length
              tab.seekPreview = -1
            }
            onCanceled: tab.seekPreview = -1
          }
        }
        Row {
          width: parent.width
          visible: tab.length > 0
          PText {
            width: parent.width / 2
            text: tab.mmss(seek.frac * tab.length)
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.6)
          }
          PText {
            width: parent.width / 2
            horizontalAlignment: Text.AlignRight
            text: tab.mmss(tab.length)
            font.pixelSize: Style.font.bodySmall
            tone: Qt.alpha(Color.popups.text, 0.6)
          }
        }

        // Transport.
        Row {
          spacing: Style.space(8)
          ActionButton {
            visible: tab.shuffleOk
            icon: "shuffle"
            selected: !!tab.p && tab.p.shuffle
            onClicked: tab.toggleShuffle()
          }
          ActionButton { icon: "prev"; enabled: !!tab.p && tab.p.canGoPrevious; onClicked: tab.p.previous() }
          ActionButton {
            icon: tab.store.playing ? "pause" : "play"
            primary: true
            enabled: !!tab.p && tab.p.canTogglePlaying
            onClicked: tab.p.togglePlaying()
          }
          ActionButton { icon: "next"; enabled: !!tab.p && tab.p.canGoNext; onClicked: tab.p.next() }
          ActionButton {
            visible: tab.loopOk
            icon: tab.loopName === "Track" ? "repeat-once" : "repeat"
            selected: tab.loopName !== "None"
            onClicked: tab.cycleRepeat()
          }
        }

        // Volume.
        Row {
          visible: tab.volumeOk
          spacing: Style.space(10)
          width: parent.width
          ActionButton {
            icon: tab.p && tab.p.volume > 0.001 ? "volume" : "volume-off"
            onClicked: tab.toggleMute()
          }
          Item {
            id: vol
            width: parent.width - Style.space(48) - parent.spacing
            height: Style.space(28)
            readonly property real v: tab.p ? tab.p.volume : 0
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: Style.space(5)
              radius: height / 2
              color: Qt.alpha(Color.popups.text, 0.12)
              Rectangle { width: parent.width * vol.v; height: parent.height; radius: height / 2; color: Color.accent }
            }
            Rectangle {
              x: vol.width * vol.v - width / 2
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(10); height: width; radius: width / 2
              color: Color.accent
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              function setAt(x) { tab.setVolume(x / width) }
              onPressed: function (m) { setAt(m.x) }
              onPositionChanged: function (m) { if (pressed) setAt(m.x) }
              onWheel: function (w) { tab.nudgeVolume(w.angleDelta.y > 0 ? 0.05 : -0.05) }
            }
          }
        }
      }
    }

    // The media apps that are running; clicking one switches to its window.
    AppRow {
      store: tab.store
      current: tab.p
      onPicked: function (player) { tab.pickApp(player) }
    }

    Visualizer {
      id: mainViz
      width: parent.width
      height: Math.max(Style.space(70), parent.height - y)
      active: tab.visible && tab.has && tab.store.playing
      bars: 48
      styleName: tab.store.cfg.visualizerStyle
    }
  }

  // [<] Style [>] in the visualizer's bottom-right corner.
  Rectangle {
    visible: tab.has && mainViz.available
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: Style.space(6)
    anchors.bottomMargin: Style.space(6)
    width: pick.implicitWidth + Style.space(8)
    height: pick.implicitHeight + Style.space(6)
    radius: Style.space(8)
    color: Qt.alpha(Color.popups.background, 0.78)
    border.width: 1
    border.color: Qt.alpha(Color.popups.text, 0.12)

    Row {
      id: pick
      anchors.centerIn: parent
      spacing: Style.space(2)
      ActionButton { icon: "left"; tooltip: "Previous visualizer"; onClicked: tab.stepVisualizer(-1) }
      PText {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(58)
        horizontalAlignment: Text.AlignHCenter
        text: Model.vizLabel(tab.vizStyle)
        font.bold: true
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideNone
      }
      ActionButton { icon: "right"; tooltip: "Next visualizer"; onClicked: tab.stepVisualizer(1) }
    }
  }

  // Nothing playing in the chosen app (or nothing running at all): say so, and
  // still list the apps so another one can be picked.
  Column {
    visible: !tab.has
    anchors.centerIn: parent
    spacing: Style.space(10)
    PText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Model.glyph("media")
      font.pixelSize: Style.space(40)
      tone: Qt.alpha(Color.popups.text, 0.3)
    }
    PText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Nothing playing"
      font.bold: true
      tone: Qt.alpha(Color.popups.text, 0.65)
    }
    PText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: tab.store.players.length > 0 ? "Pick an app to switch to it." : "Start something in any media app."
      font.pixelSize: Style.font.bodySmall
      tone: Qt.alpha(Color.popups.text, 0.45)
    }
    AppRow {
      anchors.horizontalCenter: parent.horizontalCenter
      store: tab.store
      current: tab.p
      onPicked: function (player) { tab.pickApp(player) }
    }
  }
}
