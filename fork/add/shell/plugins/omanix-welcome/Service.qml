import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// omanix.welcome (DESIGN §h.7): opens the checklist once, at the first login
// (until it is dismissed), and on `omarchy-shell omanix.welcome open`.
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  readonly property string doneFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omanix/done/welcome"

  function open() { if (root.shell) root.shell.summon("omanix.welcome", "{}") }

  Process {
    id: firstCheck
    command: ["test", "-e", root.doneFile]
    onExited: function(code) { if (code !== 0) firstOpen.start() }
  }
  // Give the bar and the session a moment before the first-boot checklist.
  Timer { id: firstOpen; interval: 4000; onTriggered: root.open() }
  // /etc/omanix/welcome.json (modules/omanix/welcome.nix): autoOpen.
  FileView {
    path: "/etc/omanix/welcome.json"
    printErrors: false
    onLoaded: {
      var c = ({})
      try { c = JSON.parse(text()) } catch (e) {}
      if (c.autoOpen !== false) firstCheck.running = true
    }
  }

  ShellIpc {
    target: "omanix.welcome"
    function open(): void { root.open() }
    function close(): void { if (root.shell) root.shell.hide("omanix.welcome") }
    function ping(): string { return "ok" }
  }
}
