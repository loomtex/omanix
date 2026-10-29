import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Change password (DESIGN §h.11): a human-only tool. The password goes from
// these fields to omanix-passwd on stdin (never argv or the environment),
// which hashes it, writes secrets/user.yaml in the human's working copy
// through sops, commits, and proposes the change: the same card as any other.
// The resident never sees any of it.
PanelWindow {
  id: root

  property bool open: false
  signal closed()

  property string status: ""
  property bool busy: false

  visible: open
  implicitWidth: Style.space(440)
  implicitHeight: column.implicitHeight + Style.space(32)
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omanix-passwd"
  WlrLayershell.layer: WlrLayer.Overlay
  // The human opened it to type a password.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  onVisibleChanged: {
    first.text = ""
    second.text = ""
    status = ""
    if (visible) first.forceActiveFocus()
  }

  function submit() {
    if (busy) return
    if (first.text !== second.text) { status = "The two passwords differ."; return }
    if (first.text.length < 8) { status = "Use at least 8 characters."; return }
    busy = true
    status = "Saving and asking for the change…"
    pendingSecret = first.text
    first.text = ""
    second.text = ""
    proc.stdinEnabled = true
    proc.running = true
  }

  property string pendingSecret: ""

  Process {
    id: proc
    command: ["omanix-passwd"]
    stdinEnabled: true
    onStarted: {
      proc.write(root.pendingSecret + "\n")
      root.pendingSecret = ""
      proc.stdinEnabled = false
    }
    stdout: StdioCollector { id: out; waitForEnd: true }
    stderr: StdioCollector { id: err; waitForEnd: true }
    onExited: function(code) {
      root.busy = false
      root.status = code === 0 ? "Done: approve the card to apply it." : String(err.text || out.text || "failed").trim().split("\n").pop()
      if (code === 0) closeTimer.start()
    }
  }

  Timer { id: closeTimer; interval: 2500; onTriggered: root.closed() }

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Commons.Color.popups.background
    border.width: Math.max(1, Style.space(2))
    border.color: Commons.Color.popups.border
    Keys.onEscapePressed: root.closed()

    Column {
      id: column
      anchors.centerIn: parent
      width: parent.width - Style.space(32)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        text: "Change your login password"
        color: Commons.Color.popups.text
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: "The new password is saved in your host repo, encrypted, and applied with a card like any other change."
        color: Util.alpha(Commons.Color.popups.text, 0.75)
        font.pixelSize: Style.font.body
      }
      TextField {
        id: first
        width: parent.width
        echoMode: TextInput.Password
        placeholderText: "New password"
        enabled: !root.busy
        onAccepted: second.forceActiveFocus()
        Keys.onEscapePressed: root.closed()
      }
      TextField {
        id: second
        width: parent.width
        echoMode: TextInput.Password
        placeholderText: "Again"
        enabled: !root.busy
        onAccepted: root.submit()
        Keys.onEscapePressed: root.closed()
      }
      Text {
        width: parent.width
        visible: root.status !== ""
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: root.status
        color: Commons.Color.popups.text
        font.pixelSize: Style.font.body
      }
      Row {
        anchors.right: parent.right
        spacing: Style.space(8)
        CardButton { text: "Cancel"; onClicked: root.closed() }
        CardButton { text: "Change password"; primary: true; onClicked: root.submit() }
      }
    }
  }
}
