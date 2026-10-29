import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The agent in the bar (DESIGN §h.3.1): glyph and state dot. Idle hollow,
// working pulsing, needs you (accent, with a count), offline or signed out
// struck. With no agent, a wrench (Change settings).
BarWidget {
  id: root
  moduleName: "omanix.chat"

  readonly property var svc: bar && bar.shell && bar.shell.services ? bar.shell.services["omanix.chat"] || null : null
  readonly property var approvals: bar && bar.shell && bar.shell.services ? bar.shell.services["omanix.approval"] || null : null
  readonly property string chatState: svc ? svc.chatState : "offline"
  readonly property int needs: (svc ? svc.questions : 0) + (approvals ? approvals.pendingCount : 0)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.chatState === "none" ? "󰖷" : "󰚩"
    labelText: root.needs > 0 ? String(root.needs) : ""
    tooltipText: root.chatState === "none" ? "Change settings" : (root.svc ? root.svc.agent : "agent") + ": " + root.chatState
    onPressed: function(b) {
      if (b === Qt.RightButton) Quickshell.execDetached(["omarchy-shell", "omanix.chat", "agent"])
      else Quickshell.execDetached(["omarchy-shell", "omanix.chat", "toggle"])
    }
  }

  // The state dot.
  Rectangle {
    id: dot
    width: Style.space(6)
    height: width
    radius: width / 2
    anchors { right: parent.right; bottom: parent.bottom; rightMargin: Style.space(3); bottomMargin: Style.space(4) }
    visible: root.chatState !== "none"
    color: root.needs > 0 ? Commons.Color.accent
      : root.chatState === "working" ? button.foreground
      : "transparent"
    border.width: 1
    border.color: root.chatState === "offline" || root.chatState === "signed-out" ? Commons.Color.urgent : button.foreground
    SequentialAnimation on opacity {
      running: root.chatState === "working"
      loops: Animation.Infinite
      onRunningChanged: if (!running) dot.opacity = 1
      NumberAnimation { to: 0.25; duration: 600 }
      NumberAnimation { to: 1; duration: 600 }
    }
  }
  // Offline or signed out: struck through.
  Rectangle {
    visible: root.chatState === "offline" || root.chatState === "signed-out"
    anchors.centerIn: parent
    width: Style.space(16)
    height: 1.5
    rotation: -45
    color: Commons.Color.urgent
  }
}
