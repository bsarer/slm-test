import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

// Full-page SLM Test chat, drawn by the Omarchy shell as an overlay.
// It talks to the local SLM Test server (http://127.0.0.1:8765), which is
// the only thing that talks to Ollama, so tools and history work the same
// as in the browser version.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "bsarer.slm-test"
  readonly property string serverUrl: "http://127.0.0.1:8765"
  readonly property string modelFilePath: Quickshell.env("HOME") + "/.local/state/slm-test/model"

  property bool opened: false
  property bool toolsOpen: false
  property bool busy: false
  property string model: "llama3.2"
  property var history: []     // messages sent to the server
  property var tools: []
  property var request: null   // the XMLHttpRequest in flight
  property var requestCtx: null
  property real appear: 0

  // Theme (shared with Omarchy's menu surfaces, so themes style this too).
  readonly property color bg: Color.menu.background
  readonly property color fg: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted
  readonly property color urgent: Color.urgent
  readonly property color subtle: Color.menu.selectedBackground
  readonly property string fontFamily: Style.font.menuFamily
  readonly property int radius: Style.cornerRadius
  readonly property int textSize: Style.font.title
  readonly property int smallSize: Style.font.bodySmall

  // ---- Shell contract: open / close / opened ----
  function open(payloadJson) {
    root.opened = true
    appearAnim.restart()
    if (root.tools.length === 0) loadTools()
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.toolsOpen = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ---- Chat ----
  function loadTools() {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
      try { root.tools = JSON.parse(xhr.responseText) } catch (e) {}
    }
    xhr.open("GET", root.serverUrl + "/tools")
    xhr.send()
  }

  function setModel(name) {
    name = String(name || "").trim()
    if (!name || name === root.model) return
    root.model = name
    modelFile.setText(name + "\n")
  }

  function newChat() {
    stop()
    root.history = []
    messages.clear()
    input.forceActiveFocus()
  }

  function stop() {
    if (root.request) {
      var r = root.request
      var ctx = root.requestCtx
      root.request = null
      r.abort()
      finish(ctx, "stopped")
    }
  }

  function scrollToEnd() {
    Qt.callLater(function() { list.positionViewAtEnd() })
  }

  function send(text) {
    text = String(text || "").trim()
    if (!text || root.busy) return
    input.text = ""
    root.toolsOpen = false

    var start = root.history.length
    root.history.push({ role: "user", content: text })
    messages.append({ kind: "user", text: text })
    messages.append({ kind: "assistant", text: "…" })

    var xhr = new XMLHttpRequest()
    var ctx = { start: start, reply: "", replyIndex: messages.count - 1, seen: 0, buf: "", error: "" }
    root.request = xhr
    root.requestCtx = ctx
    root.busy = true
    scrollToEnd()

    xhr.onreadystatechange = function() {
      if (root.request !== xhr) return
      if (xhr.readyState === XMLHttpRequest.LOADING || xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) readChunks(xhr, ctx, xhr.readyState === XMLHttpRequest.DONE)
      }
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status !== 200) {
          var msg = "Can't reach the SLM Test server at " + root.serverUrl + ". Try: systemctl --user start slm-test"
          if (xhr.status > 0) {
            try { msg = JSON.parse(xhr.responseText).error || msg } catch (e) { msg = "HTTP " + xhr.status }
          }
          ctx.error = msg
        }
        root.request = null
        finish(ctx, "")
      }
    }
    xhr.open("POST", root.serverUrl + "/chat")
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.send(JSON.stringify({ model: root.model, messages: root.history, tools: true }))
  }

  // Parse the newline-delimited JSON the server streams back.
  function readChunks(xhr, c, final) {
    var all = xhr.responseText
    c.buf += all.substring(c.seen)
    c.seen = all.length
    var lines = c.buf.split("\n")
    c.buf = final ? "" : lines.pop()
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].trim()) continue
      var chunk
      try { chunk = JSON.parse(lines[i]) } catch (e) { continue }
      if (chunk.error) { c.error = chunk.error; continue }
      if (chunk.notice) { insertBeforeReply(c, "notice", chunk.notice); continue }
      if (chunk.tool_event) {
        var t = chunk.tool_event
        insertBeforeReply(c, t.ok ? "tool" : "toolfail",
                          t.icon + "  " + (t.ok ? "Opened " : "Couldn't open ") + t.label)
        continue
      }
      if (chunk.history) {
        for (var h = 0; h < chunk.history.length; h++) root.history.push(chunk.history[h])
        c.reply = ""
        continue
      }
      if (chunk.message && chunk.message.content) {
        c.reply += chunk.message.content
        messages.setProperty(c.replyIndex, "text", c.reply)
      }
      if (chunk.done && chunk.eval_count) {
        var secs = chunk.eval_duration / 1e9
        c.stats = chunk.eval_count + " tokens · " + (chunk.eval_count / secs).toFixed(1) + " tok/s · "
                + (chunk.total_duration / 1e9).toFixed(1) + "s total"
      }
    }
    scrollToEnd()
  }

  function insertBeforeReply(c, kind, text) {
    messages.insert(c.replyIndex, { kind: kind, text: text })
    c.replyIndex++
  }

  function finish(c, how) {
    if (c.done) return
    c.done = true
    if (c.reply) {
      root.history.push({ role: "assistant", content: c.reply })
      if (c.stats) messages.append({ kind: "stats", text: c.stats })
    } else {
      messages.remove(c.replyIndex)
      if (root.history.length <= c.start + 1) root.history.splice(c.start)  // let the question be retried
    }
    if (how === "stopped") messages.append({ kind: "stats", text: "stopped" })
    if (c.error) messages.append({ kind: "error", text: c.error })
    root.busy = false
    scrollToEnd()
    if (root.opened) input.forceActiveFocus()
  }

  ListModel { id: messages }

  FileView {
    id: modelFile
    path: root.modelFilePath
    printErrors: false
    onLoaded: {
      var name = text().trim()
      if (name) root.model = name
    }
  }

  NumberAnimation {
    id: appearAnim
    target: root
    property: "appear"
    from: 0
    to: 1
    duration: 180
    easing.type: Easing.OutCubic
  }

  // Small flat button used in the header and input row.
  component ChatButton: Rectangle {
    id: btn
    property string label: ""
    property bool primary: false
    property bool active: false
    signal clicked()
    implicitWidth: btnText.implicitWidth + 22
    implicitHeight: btnText.implicitHeight + 12
    radius: root.radius
    color: primary ? root.accent : (btnMouse.containsMouse || active ? root.subtle : "transparent")
    border.width: primary ? 0 : 1
    border.color: active ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
    Text {
      id: btnText
      anchors.centerIn: parent
      text: btn.label
      color: btn.primary ? root.bg : (btn.active ? root.accent : root.fg)
      font.family: root.fontFamily
      font.pixelSize: root.smallSize + 1
      font.bold: btn.primary
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "slm-test-chat"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Dim the desktop; clicking outside the card closes the chat.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      opacity: root.appear
    }
    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: Math.min(1100, parent.width - 64)
      height: parent.height - 64
      radius: root.radius
      color: root.bg
      border.width: 1
      border.color: Qt.rgba(root.border.r, root.border.g, root.border.b, 0.35)
      opacity: root.appear
      scale: 0.97 + 0.03 * root.appear

      MouseArea { anchors.fill: parent }  // swallow clicks so they don't close the chat

      Keys.onEscapePressed: root.toolsOpen ? (root.toolsOpen = false) : root.dismiss()

      // ---- Header ----
      Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
        height: 36

        Rectangle {
          id: dot
          anchors.verticalCenter: parent.verticalCenter
          width: 14; height: 14; radius: 7
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.45) }
            GradientStop { position: 1.0; color: Qt.darker(root.accent, 1.25) }
          }
          SequentialAnimation on opacity {
            running: root.busy
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 450 }
            NumberAnimation { to: 1.0; duration: 450 }
            onRunningChanged: if (!running) dot.opacity = 1
          }
        }
        Text {
          anchors { left: dot.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
          text: "SLM Test"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Row {
          anchors { right: parent.right; verticalCenter: parent.verticalCenter }
          spacing: 8

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Model"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: root.smallSize + 1
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 150; height: 30
            radius: root.radius
            color: "transparent"
            border.width: 1
            border.color: modelInput.activeFocus ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)
            TextInput {
              id: modelInput
              anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
              verticalAlignment: TextInput.AlignVCenter
              text: root.model
              color: root.fg
              selectionColor: root.accent
              font.family: root.fontFamily
              font.pixelSize: root.smallSize + 1
              clip: true
              onEditingFinished: root.setModel(text)
              Keys.onEscapePressed: { text = root.model; input.forceActiveFocus() }
            }
          }
          ChatButton {
            label: "🔧 Tools"
            active: root.toolsOpen
            onClicked: root.toolsOpen = !root.toolsOpen
          }
          ChatButton { label: "New chat"; onClicked: root.newChat() }
          ChatButton { label: "✕"; onClicked: root.dismiss() }
        }
      }

      // ---- Tools drawer ----
      Rectangle {
        id: toolsPanel
        visible: root.toolsOpen
        anchors { top: header.bottom; left: parent.left; right: parent.right; margins: 18; topMargin: 12 }
        height: visible ? toolsCol.implicitHeight + 24 : 0
        radius: root.radius
        color: root.subtle

        Column {
          id: toolsCol
          anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
          spacing: 10
          Text {
            text: root.tools.length ? "What the model can open — just ask in your own words, or click one to try it:"
                                    : "Loading tools…"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: root.smallSize + 1
          }
          Flow {
            width: parent.width
            spacing: 8
            Repeater {
              model: root.tools
              delegate: Rectangle {
                required property var modelData
                width: chipText.implicitWidth + 20
                height: chipText.implicitHeight + 12
                radius: root.radius
                color: chipMouse.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.15) : root.bg
                border.width: 1
                border.color: chipMouse.containsMouse ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                Text {
                  id: chipText
                  anchors.centerIn: parent
                  textFormat: Text.StyledText
                  text: modelData.icon + "  <b>" + modelData.label + "</b>  <font color='" + root.muted
                        + "'>“" + modelData.example + "”</font>"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: root.smallSize + 1
                }
                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    input.text = modelData.example
                    input.cursorPosition = input.length
                    root.toolsOpen = false
                    input.forceActiveFocus()
                  }
                }
              }
            }
          }
        }
      }

      // ---- Messages ----
      ListView {
        id: list
        anchors {
          top: toolsPanel.visible ? toolsPanel.bottom : header.bottom
          bottom: inputBox.top
          left: parent.left; right: parent.right
          topMargin: 12; bottomMargin: 12; leftMargin: 18; rightMargin: 18
        }
        clip: true
        spacing: 10
        model: messages
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
          id: row
          required property int index
          required property string kind
          required property string text
          readonly property bool isUser: kind === "user"
          readonly property bool isBubble: kind === "user" || kind === "assistant"
          readonly property real maxWidth: list.width * (isBubble ? 0.78 : 1.0)
          width: list.width
          height: bubble.height

          Text {
            id: measure
            visible: false
            text: row.text
            font: body.font
          }

          Rectangle {
            id: bubble
            anchors.right: row.isUser ? parent.right : undefined
            anchors.left: row.isUser ? undefined : parent.left
            anchors.horizontalCenter: row.kind === "error" ? parent.horizontalCenter : undefined
            width: body.width + (row.isBubble ? 26 : (row.kind === "tool" || row.kind === "toolfail" ? 22 : 0))
            height: body.height + (row.isBubble ? 18 : (row.kind === "tool" || row.kind === "toolfail" ? 10 : 0))
            radius: row.isBubble ? Math.max(root.radius, 2) : Math.max(root.radius, height / 2)
            color: row.kind === "user" ? root.accent
                 : row.kind === "assistant" ? root.subtle
                 : "transparent"
            border.width: row.kind === "tool" || row.kind === "toolfail" ? 1 : 0
            border.color: row.kind === "toolfail" ? root.urgent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25)

            TextEdit {
              id: body
              anchors.centerIn: parent
              width: Math.min(measure.implicitWidth + 2, row.maxWidth - (row.isBubble ? 26 : 0))
              text: row.text
              readOnly: true
              selectByMouse: true
              wrapMode: TextEdit.Wrap
              textFormat: TextEdit.PlainText
              selectionColor: row.isUser ? root.bg : root.accent
              selectedTextColor: row.isUser ? root.accent : root.bg
              color: row.kind === "user" ? root.bg
                   : row.kind === "error" || row.kind === "toolfail" ? root.urgent
                   : row.kind === "stats" || row.kind === "notice" || row.kind === "tool" ? root.muted
                   : root.fg
              font.family: root.fontFamily
              font.pixelSize: row.isBubble ? root.textSize : root.smallSize
            }
          }
        }

        // Empty state
        Column {
          anchors.centerIn: parent
          visible: messages.count === 0
          spacing: 8
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Chat with " + root.model + " on this computer"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Enter to send · Shift+Enter for a new line · Esc to close\nOpen 🔧 Tools to see which Omarchy panels it can open."
            horizontalAlignment: Text.AlignHCenter
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: root.smallSize + 1
          }
        }
      }

      // ---- Input ----
      Rectangle {
        id: inputBox
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 18 }
        height: Math.min(input.contentHeight, 160) + 24
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: input.activeFocus ? root.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.18)

        Flickable {
          id: inputScroll
          anchors { left: parent.left; right: sendBtn.left; top: parent.top; bottom: parent.bottom; margins: 12 }
          contentHeight: input.contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          TextEdit {
            id: input
            width: inputScroll.width
            wrapMode: TextEdit.Wrap
            color: root.fg
            selectionColor: root.accent
            selectedTextColor: root.bg
            font.family: root.fontFamily
            font.pixelSize: root.textSize
            focus: true
            onCursorRectangleChanged: {
              if (cursorRectangle.y + cursorRectangle.height > inputScroll.contentY + inputScroll.height)
                inputScroll.contentY = cursorRectangle.y + cursorRectangle.height - inputScroll.height
              else if (cursorRectangle.y < inputScroll.contentY)
                inputScroll.contentY = cursorRectangle.y
            }
            Keys.onPressed: function(event) {
              if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                  && !(event.modifiers & Qt.ShiftModifier)) {
                if (root.busy) root.stop()
                else root.send(input.text)
                event.accepted = true
              } else if (event.key === Qt.Key_Escape) {
                if (root.toolsOpen) root.toolsOpen = false
                else root.dismiss()
                event.accepted = true
              }
            }

            Text {
              visible: !input.text
              text: root.busy ? "Thinking… (Enter to stop)" : "Message " + root.model + "…"
              color: root.muted
              font: input.font
            }
          }
        }

        ChatButton {
          id: sendBtn
          anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
          label: root.busy ? "Stop" : "Send"
          primary: !root.busy
          onClicked: root.busy ? root.stop() : root.send(input.text)
        }
      }
    }
  }
}
