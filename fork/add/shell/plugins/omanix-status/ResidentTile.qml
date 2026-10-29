import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// The resident in the Agents panel (P13): read-only. Its account is not one
// of the human's harness accounts; it is another user with its own login.
Rectangle {
  id: root

  property var shell: null
  property color foreground: Commons.Color.popups.text
  readonly property var chat: shell && shell.services ? shell.services["omanix.chat"] || null : null
  readonly property string chatState: chat ? chat.chatState : "none"

  visible: chatState !== "none"
  implicitHeight: visible ? column.implicitHeight + Style.space(16) : 0
  radius: Style.cornerRadius
  color: Util.alpha(foreground, 0.05)

  Column {
    id: column
    x: Style.space(8)
    y: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(4)
    Text {
      textFormat: Text.PlainText
      text: "󰚩  " + (root.chat ? root.chat.agent : "") + " · this computer's agent"
      color: root.foreground
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }
    Text {
      width: parent.width
      wrapMode: Text.Wrap
      textFormat: Text.PlainText
      text: ({ idle: "Ready", working: "Working", blocked: "Waiting for you", offline: "Offline", "signed-out": "Signed out" })[root.chatState]
        + " · signs in with its own account, separate from yours"
      color: Util.alpha(root.foreground, 0.75)
      font.pixelSize: Style.font.body
    }
    Text {
      textFormat: Text.PlainText
      text: "Open the chat ›"
      color: Commons.Color.accent
      font.pixelSize: Style.font.body
      MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Quickshell.execDetached(["omarchy-shell", "omanix.chat", "open"]) }
    }
  }
}
