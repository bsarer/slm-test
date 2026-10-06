import QtQuick
import qs.Commons

// SLM Test orb: a small glowing dot in the bar.
//   left click  -> toggle the full-page chat overlay (same as Super+Ctrl+M)
//   right click -> open the chat in the browser instead
// It breathes slowly when ready, pulses while the model is answering,
// and dims when the SLM Test server or Ollama isn't reachable.
Item {
  id: root

  property var bar
  property string moduleName
  property var settings

  readonly property string pluginId: "bsarer.slm-test"
  readonly property string serverUrl: "http://127.0.0.1:8765"

  property bool serverUp: false
  property bool ollamaUp: false
  property bool busy: false
  readonly property bool ready: serverUp && ollamaUp

  readonly property int size: bar && bar.barSize > 0 ? bar.barSize : 26
  readonly property color orbColor: ready ? Color.accent : Color.muted

  implicitWidth: size + 4
  implicitHeight: size

  function toggleChat() {
    if (!bar) return
    // Start the server if it isn't running yet (a no-op when it is), then toggle.
    bar.run("systemctl --user start slm-test.service >/dev/null 2>&1; omarchy-shell shell toggle "
            + root.pluginId + " '{}'")
  }

  function poll() {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      if (xhr.status === 200) {
        try {
          var h = JSON.parse(xhr.responseText)
          root.serverUp = true
          root.ollamaUp = h.ollama === true
          root.busy = h.busy === true
          return
        } catch (e) {}
      }
      root.serverUp = false
      root.ollamaUp = false
      root.busy = false
    }
    xhr.open("GET", root.serverUrl + "/health")
    xhr.send()
  }

  Timer {
    interval: root.busy ? 1000 : 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.poll()
  }

  // Soft glow behind the orb.
  Rectangle {
    id: glow
    anchors.centerIn: parent
    width: root.size * 0.82
    height: width
    radius: width / 2
    color: root.orbColor
    opacity: root.ready ? 0.22 : 0.0

    SequentialAnimation on opacity {
      running: root.ready
      loops: Animation.Infinite
      NumberAnimation { to: root.busy ? 0.55 : 0.32; duration: root.busy ? 450 : 1800; easing.type: Easing.InOutSine }
      NumberAnimation { to: 0.12; duration: root.busy ? 450 : 1800; easing.type: Easing.InOutSine }
    }
  }

  // The orb itself.
  Rectangle {
    id: core
    anchors.centerIn: parent
    width: root.size * 0.48
    height: width
    radius: width / 2
    opacity: root.ready ? 1.0 : 0.45
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.lighter(root.orbColor, 1.45) }
      GradientStop { position: 1.0; color: Qt.darker(root.orbColor, 1.25) }
    }

    SequentialAnimation on scale {
      running: root.busy
      loops: Animation.Infinite
      NumberAnimation { to: 1.18; duration: 450; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 450; easing.type: Easing.InOutSine }
      onRunningChanged: if (!running) core.scale = 1.0
    }

    // Little highlight so it reads as a sphere.
    Rectangle {
      x: parent.width * 0.2
      y: parent.height * 0.14
      width: parent.width * 0.34
      height: width
      radius: width / 2
      color: "white"
      opacity: 0.45
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(event) {
      if (!root.bar) return
      if (event.button === Qt.RightButton)
        root.bar.run("systemctl --user start slm-test.service >/dev/null 2>&1; sleep 0.3; xdg-open " + root.serverUrl)
      else
        root.toggleChat()
    }
    onContainsMouseChanged: {
      if (!root.bar) return
      if (containsMouse) {
        var state = !root.serverUp ? "server not running (click to start)"
                  : !root.ollamaUp ? "Ollama is not running"
                  : root.busy ? "thinking…" : "ready"
        root.bar.showTooltip(mouse, "SLM Test: " + state + "\nClick or Super+Ctrl+M to chat · right-click for browser")
      } else {
        root.bar.hideTooltip(mouse)
      }
    }
  }
}
