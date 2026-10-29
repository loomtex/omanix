import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "ChatModel.js" as ChatModel

// The chat panel (DESIGN §h.3.1): a right-edge drawer. Opened only by the
// human (SUPER + A, the bar widget, a menu intent), so it takes the keyboard
// when it opens (on-demand: clicking a window gives it back).
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var service: null
  readonly property var svc: service || (shell && shell.services ? shell.services["omanix.chat"] || null : null)

  property bool opened: false

  function open(payloadJson) { opened = true; Qt.callLater(focusComposer) }
  function close() { opened = false }
  function focusComposer() { composer.forceActiveFocus(); composer.cursorPosition = composer.text.length }

  // The service owns the composer text (a prefill can arrive while closed).
  Connections {
    target: root.svc
    ignoreUnknownSignals: true
    function onComposerFocusRequested() { Qt.callLater(root.focusComposer) }
    function onComposerTextChanged() { if (composer.text !== root.svc.composerText) composer.text = root.svc.composerText }
  }
  onSvcChanged: if (svc) composer.text = svc.composerText

  readonly property color fg: Commons.Color.popups.text
  readonly property color bg: Commons.Color.popups.background
  readonly property string agentName: svc ? svc.agent : "ada"
  readonly property string chatState: svc ? svc.chatState : "offline"

  PanelWindow {
    id: drawer
    visible: root.opened
    anchors { top: true; bottom: true; right: true }
    implicitWidth: Math.max(Style.space(420), Math.round((screen ? screen.width : 1280) * 0.34))
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.namespace: "omanix-chat"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      anchors.fill: parent
      color: root.bg
      border.width: 1
      border.color: Commons.Color.popups.border
      Keys.onEscapePressed: root.shell ? root.shell.hide("omanix.chat") : root.close()

      Column {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(12) }
        spacing: Style.space(6)

        Item {
          width: parent.width
          height: Style.space(28)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰚩  " + root.agentName + "  ·  " + ({ idle: "ready", working: "working…", blocked: "waiting for you",
              offline: "offline", "signed-out": "signed out", none: "no agent" })[root.chatState]
            color: root.fg
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)
            ChatButton { text: "New chat"; visible: root.chatState !== "none"; onClicked: { if (root.svc) { root.svc.send({ t: "new-session" }); root.svc.transcript.clear() } } }
            ChatButton { text: root.svc && root.svc.view === "agent" ? "Chat" : "Agent"; onClicked: if (root.svc) root.svc.view = root.svc.view === "agent" ? "chat" : "agent" }
            ChatButton { text: "✕"; onClicked: root.shell ? root.shell.hide("omanix.chat") : root.close() }
          }
        }

        // Offline / signed out: say so, and offer the way back (§h.3.6, §h.11).
        Rectangle {
          visible: root.chatState === "offline" || root.chatState === "signed-out" || root.chatState === "none"
          width: parent.width
          height: bannerText.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Util.alpha(Commons.Color.urgent, 0.15)
          Text {
            id: bannerText
            anchors { left: parent.left; right: signIn.left; verticalCenter: parent.verticalCenter; margins: Style.space(6) }
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: root.fg
            font.pixelSize: Style.font.body
            text: root.chatState === "none" ? "No agent on this computer. Change settings yourself: the menu's rows open their how-to."
              : root.chatState === "signed-out" ? root.agentName + " is signed out."
              : root.agentName + " isn't reachable right now. Cards and the GUI tools still work."
          }
          ChatButton {
            id: signIn
            visible: root.chatState === "signed-out" || root.chatState === "offline"
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; margins: Style.space(6) }
            text: "Sign in " + root.agentName
            onClicked: Quickshell.execDetached(["xdg-terminal-exec", "--app-id=org.omanix.agent-login", "loom-agent-login", root.agentName])
          }
        }
      }

      // ---- body ----------------------------------------------------------
      Item {
        id: body
        anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: footer.top; margins: Style.space(12) }

        ListView {
          id: transcriptView
          anchors.fill: parent
          visible: !root.svc || root.svc.view === "chat"
          clip: true
          spacing: Style.space(8)
          model: root.svc ? root.svc.transcript : null
          onCountChanged: Qt.callLater(function() { transcriptView.positionViewAtEnd() })

          delegate: Item {
            id: row
            required property string kind
            required property string text
            required property string detail
            required property string payload
            readonly property var extra: { try { return JSON.parse(payload) } catch (e) { return ({}) } }
            width: transcriptView.width
            height: content.implicitHeight

            Column {
              id: content
              width: row.kind === "human" ? Math.min(implicitWidth, parent.width * 0.85) : parent.width
              anchors.right: row.kind === "human" ? parent.right : undefined
              spacing: Style.space(4)

              Rectangle {
                visible: row.kind === "human" || row.kind === "agent"
                width: parent.width
                height: bubbleText.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: row.kind === "human" ? Util.alpha(Commons.Color.accent, 0.18) : "transparent"
                Text {
                  id: bubbleText
                  x: Style.space(6); y: Style.space(6)
                  width: parent.width - Style.space(12)
                  wrapMode: Text.Wrap
                  // agent text: the safe Markdown subset (ChatModel.markdown
                  // escapes everything before adding its own tags)
                  textFormat: row.kind === "agent" ? Text.StyledText : Text.PlainText
                  text: row.kind === "agent" ? ChatModel.markdown(row.text) : row.text
                  color: root.fg
                  font.pixelSize: Style.font.body
                }
              }
              Text {
                visible: row.kind === "human" && row.detail !== ""
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: row.detail
                color: Util.alpha(root.fg, 0.5)
                font.pixelSize: Style.font.caption
              }
              Text {
                visible: row.kind === "activity" || row.kind === "progress" || row.kind === "notice"
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: (row.kind === "progress" ? "⟳ " : "· ") + row.text
                color: row.extra.external ? Commons.Color.urgent : Util.alpha(root.fg, 0.6)
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                visible: row.kind === "error" || row.kind === "rolledback"
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: row.text
                color: Commons.Color.urgent
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              Row {
                visible: row.kind === "card" || row.kind === "applied" || row.kind === "rolledback"
                spacing: Style.space(6)
                Text { textFormat: Text.PlainText; text: row.kind === "card" ? "⛉ " + row.text : (row.kind === "applied" ? "✓ " + row.text : ""); color: root.fg; font.pixelSize: Style.font.body }
                ChatButton { visible: row.kind === "card"; text: "Show card"; onClicked: Quickshell.execDetached(["omarchy-shell", "omanix.approval", "open"]) }
                ChatButton { visible: row.kind === "applied"; text: "Undo"; onClicked: Quickshell.execDetached(["loom", "undo"]) }
                ChatButton { visible: row.kind === "rolledback"; text: "Why?"; onClicked: if (root.svc) { root.svc.composerText = "Why was my last change rolled back?"; root.focusComposer() } }
              }
              Column {
                visible: row.kind === "question"
                width: parent.width
                spacing: Style.space(4)
                Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: row.text; color: root.fg; font.pixelSize: Style.font.body }
                Flow {
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: row.extra.choices || []
                    ChatButton {
                      required property var modelData
                      text: String(modelData)
                      outlined: true
                      tooltip: "suggested by " + root.agentName
                      onClicked: if (root.svc) { root.svc.composerText = String(modelData); root.svc.submit() }
                    }
                  }
                }
                Text { textFormat: Text.PlainText; text: "suggested by " + root.agentName; color: Util.alpha(root.fg, 0.5); font.pixelSize: Style.font.caption }
              }
              Row {
                visible: row.kind === "auth"
                spacing: Style.space(6)
                Text { textFormat: Text.PlainText; text: "Sign-in page on " + row.text; color: root.fg; font.pixelSize: Style.font.body }
                // The human's default browser binary with the URL as an
                // argument; never xdg-open (no custom-scheme handlers).
                ChatButton { text: "Open in browser"; onClicked: Quickshell.execDetached(["omarchy-launch-browser", String(row.extra.url || "")]) }
              }
            }
          }
        }

        // Do it yourself: the row's how-to (§h.11), when there's no agent to ask.
        Column {
          anchors.fill: parent
          visible: !!root.svc && root.svc.view === "diy"
          spacing: Style.space(8)
          Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: root.fg; font.pixelSize: Style.font.title; font.bold: true
            text: root.svc && root.svc.diy ? "Do it yourself: " + root.svc.diy.label : "" }
          Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: root.fg; font.pixelSize: Style.font.body
            text: "Edit your host repo (~/omanix-host), commit, then Apply (loom propose); you get the same card." }
          Rectangle {
            width: parent.width
            height: manual.implicitHeight + Style.space(12)
            color: Util.alpha(root.fg, 0.06)
            radius: Style.cornerRadius
            Text { id: manual; x: Style.space(6); y: Style.space(6); width: parent.width - Style.space(12); wrapMode: Text.Wrap; textFormat: Text.PlainText
              color: root.fg; font.family: Style.font.family; font.pixelSize: Style.font.body
              text: root.svc && root.svc.diy ? root.svc.diy.manual : "" }
          }
          Row {
            spacing: Style.space(6)
            ChatButton { text: "Open host repo"; onClicked: Quickshell.execDetached(["omanix", "repo", "open"]) }
            ChatButton { text: "Copy snippet"; onClicked: Quickshell.execDetached(["wl-copy", root.svc && root.svc.diy ? root.svc.diy.manual : ""]) }
            ChatButton { text: "Ask " + root.agentName + " anyway"; visible: root.chatState !== "none"; onClicked: if (root.svc) root.svc.view = "chat" }
          }
        }

        Column {
          anchors.fill: parent
          visible: !!root.svc && root.svc.view === "options"
          spacing: Style.space(8)
          Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: root.fg; font.pixelSize: Style.font.title; font.bold: true; text: "What can I change?" }
          Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: root.fg; font.pixelSize: Style.font.body
            text: "Look, apps, input, displays, power, network, security and updates are all yours to change: ask " + root.agentName
              + ", or browse the options (omanix options <words> in a terminal)." }
          ChatButton { text: "Ask " + root.agentName + ": what can I change?"; visible: root.chatState !== "none"
            onClicked: if (root.svc) { root.svc.view = "chat"; root.svc.composerText = "What can I change on this computer?"; root.focusComposer() } }
        }

        Column {
          anchors.fill: parent
          visible: !!root.svc && root.svc.view === "agent"
          spacing: Style.space(8)
          Text { width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: root.fg; font.pixelSize: Style.font.body
            text: root.agentName + " is a separate user on this computer (" + root.chatState + "). It can't see your screen or files; you hand it what it needs." }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            ChatButton { text: "Sign in again"; onClicked: Quickshell.execDetached(["xdg-terminal-exec", "--app-id=org.omanix.agent-login", "loom-agent-login", root.agentName]) }
            ChatButton { text: "Open in terminal"; onClicked: Quickshell.execDetached(["xdg-terminal-exec", "portal-" + root.agentName]) }
            ChatButton { text: "Stop"; onClicked: if (root.svc) root.svc.send({ t: "stop" }) }
            ChatButton { text: "Do it myself"; onClicked: if (root.svc) root.svc.view = "diy" }
          }
        }
      }

      // ---- composer --------------------------------------------------------
      Column {
        id: footer
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Style.space(12) }
        spacing: Style.space(6)

        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.svc && root.svc.composerText === "" && root.svc.chips.length > 0
          Repeater {
            model: root.svc ? root.svc.chips : []
            ChatButton {
              required property var modelData
              text: modelData.label
              outlined: true
              onClicked: if (root.svc) { root.svc.composerText = modelData.text; root.focusComposer() }
            }
          }
        }

        Text {
          visible: !!root.svc && root.svc.source !== ""
          textFormat: Text.PlainText
          text: root.svc ? root.svc.source : ""
          color: Util.alpha(root.fg, 0.6)
          font.pixelSize: Style.font.caption
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: !!root.svc && root.svc.attachments.length > 0
          Repeater {
            model: root.svc ? root.svc.attachments : []
            ChatButton {
              required property var modelData
              text: "📎 " + modelData.name + " · " + Math.max(1, Math.round(modelData.size / 1024)) + " KB  ✕"
              tooltip: modelData.preview
              onClicked: if (root.svc) root.svc.removeAttachment(modelData.ref)
            }
          }
        }

        Rectangle {
          width: parent.width
          height: Math.min(Style.space(160), Math.max(Style.space(40), composer.implicitHeight + Style.space(12)))
          radius: Style.cornerRadius
          color: Util.alpha(root.fg, 0.05)
          border.width: 1
          border.color: composer.activeFocus ? Commons.Color.accent : Util.alpha(root.fg, 0.25)
          ScrollView {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            TextArea {
              id: composer
              wrapMode: TextEdit.Wrap
              textFormat: TextEdit.PlainText
              placeholderText: root.chatState === "none" ? "No agent on this computer" : "Ask " + root.agentName + "…"
              color: root.fg
              font.pixelSize: Style.font.body
              background: null
              onTextChanged: if (root.svc && root.svc.composerText !== text) root.svc.composerText = text
              // Enter sends, Shift+Enter is a newline, Escape sends nothing.
              Keys.onPressed: function(event) {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                  event.accepted = true
                  if (root.svc) root.svc.submit()
                } else if (event.key === Qt.Key_Escape) {
                  event.accepted = true
                  if (root.shell) root.shell.hide("omanix.chat"); else root.close()
                }
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(30)
          Row {
            spacing: Style.space(6)
            ChatButton { text: "Attach file"; onClicked: if (root.svc) root.svc.attach("file", "") }
            ChatButton { text: "Clipboard"; onClicked: if (root.svc) root.svc.attach("clipboard", "") }
            ChatButton { text: "Screenshot"; onClicked: if (root.svc) root.svc.attach("screenshot", "") }
          }
          Row {
            anchors.right: parent.right
            spacing: Style.space(6)
            ChatButton { text: "Stop"; visible: root.chatState === "working"; onClicked: if (root.svc) root.svc.send({ t: "stop" }) }
            ChatButton { text: "Send"; primary: true; enabled: root.chatState !== "none"; onClicked: if (root.svc) root.svc.submit() }
          }
        }
      }
    }
  }
}
