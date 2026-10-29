import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// omanix.status (DESIGN §h.2, P7): two indicators that show only when they
// matter. "Approval pending" (the shield, with the count) opens the card;
// "agent offline" opens the chat's agent view (sign in, restart).
BarWidget {
  id: root
  moduleName: "omanix.status"

  readonly property var services: bar && bar.shell && bar.shell.services ? bar.shell.services : ({})
  readonly property var approvals: services["omanix.approval"] || null
  readonly property var chat: services["omanix.chat"] || null
  readonly property int pending: approvals ? approvals.pendingCount : 0
  readonly property string chatState: chat ? chat.chatState : "none"
  readonly property bool offline: chatState === "offline" || chatState === "signed-out"

  visible: pending > 0 || offline
  implicitWidth: row.implicitWidth
  implicitHeight: Math.max(approval.implicitHeight, agentDown.implicitHeight)

  ShellIpc {
    target: "omanix.status"
    function state(): string { return JSON.stringify({ visible: root.visible, pending: root.pending, offline: root.offline, chat: root.chatState }) }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter

    BarIconButton {
      id: approval
      visible: root.pending > 0
      bar: root.bar
      text: "󰒃"
      labelText: root.pending > 1 ? String(root.pending) : ""
      active: true
      useActiveColor: true
      activeColor: Commons.Color.accent
      tooltipText: root.pending === 1 ? "An approval card is waiting" : root.pending + " approval cards are waiting"
      onPressed: Quickshell.execDetached(["omarchy-shell", "omanix.approval", "open"])
    }
    BarIconButton {
      id: agentDown
      visible: root.offline
      bar: root.bar
      text: "󱚧"
      active: true
      useActiveColor: true
      activeColor: Commons.Color.urgent
      tooltipText: (root.chat ? root.chat.agent : "the agent") + (root.chatState === "signed-out" ? " is signed out" : " is offline")
      onPressed: Quickshell.execDetached(["omarchy-shell", "omanix.chat", "agent"])
    }
  }
}
