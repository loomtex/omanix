import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// The first-boot checklist and the static tour (DESIGN §h.7). Every check
// reads local state; nothing here talks to the agent.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property int slide: -1   // -1: the checklist; 0..4: the tour

  readonly property var chat: shell && shell.services ? shell.services["omanix.chat"] || null : null
  readonly property string agent: chat ? chat.agent : "ada"
  readonly property string chatState: chat ? chat.chatState : "none"
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omanix/done"

  property var checks: ({})

  function open(payloadJson) { opened = true; slide = -1; refresh() }
  function close() { opened = false }
  function dismiss() {
    Quickshell.execDetached(["bash", "-c", "mkdir -p \"$1\" && touch \"$1/welcome\"", "welcome", stateDir])
    if (shell) shell.hide("omanix.welcome"); else close()
  }
  function mark(name) {
    Quickshell.execDetached(["bash", "-c", "mkdir -p \"$1\" && touch \"$1/$2\"", "welcome", stateDir, name])
    var next = ({}); for (var k in checks) next[k] = checks[k]; next[name] = true; checks = next
  }
  function refresh() { if (!checkProc.running) checkProc.running = true }

  Process {
    id: checkProc
    command: ["bash", "-c",
      "net=false; [ \"$(nmcli -t -f CONNECTIVITY general 2>/dev/null)\" = full ] && net=true; "
      + "pub=false; [ -e /persist/var/lib/loom/firstboot/repo-publish.done ] && pub=true; "
      + "sek=false; [ -e \"$1/sek-written\" ] && sek=true; rev=false; [ -e \"$1/reviewer\" ] && rev=true; "
      + "printf '{\"network\":%s,\"published\":%s,\"sek\":%s,\"reviewer\":%s}\\n' $net $pub $sek $rev", "checks", root.stateDir]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.checks = JSON.parse(text) } catch (e) {} } }
  }
  Timer { interval: 3000; repeat: true; running: root.opened; onTriggered: root.refresh() }

  readonly property var tour: [
    { title: "Things you do, and things you change", text: "SUPER + SPACE opens the menu. Things you do (screenshots, Wi-Fi, volume, themes) happen right there. Things you change about the computer become a request to " + agent + "." },
    { title: "Ask " + agent, text: "SUPER + A opens the chat. Ask in your own words; " + agent + " edits this computer's configuration and asks you before anything changes." },
    { title: "Read the card", text: "EXAMPLE — nothing will change.\n\n“install steam and set it up for gaming” · +3 pkgs · Reviewer: matches\n\nThe quote is your request. The packages and files come from the computer itself. The review is another AI's reading and can be wrong. Details shows the diffs." },
    { title: "Undo", text: "After a change, the Undo toast puts the last system back in seconds; a change that breaks the desktop is rolled back by itself." },
    { title: "What can I change?", text: "Menu › What can I change? lists what you can ask for, and how to do each thing yourself." }
  ]

  PanelWindow {
    visible: root.opened
    implicitWidth: Style.space(560)
    implicitHeight: content.implicitHeight + Style.space(40)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omanix-welcome"
    WlrLayershell.layer: WlrLayer.Top
    // It opens by itself at the first login: no keyboard until clicked.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Commons.Color.popups.background
      border.width: Math.max(1, Style.space(2))
      border.color: Commons.Color.popups.border

      Column {
        id: content
        anchors.centerIn: parent
        width: parent.width - Style.space(40)
        spacing: Style.space(10)

        Text { textFormat: Text.PlainText; font.pixelSize: Style.font.heading; font.bold: true; color: Commons.Color.popups.text
          text: root.slide < 0 ? "Welcome to omanix" : root.tour[root.slide].title }

        Column {
          visible: root.slide < 0
          width: parent.width
          spacing: Style.space(8)
          Repeater {
            model: [
              { id: "network", label: "Network", done: root.checks.network === true, action: "Connect", run: ["omarchy-shell", "shell", "summon", "omarchy.network"] },
              { id: "published", label: "Publish this computer's configuration", done: root.checks.published !== false, action: "", run: [] },
              { id: "sek", label: "Write down your system encryption key (shown once at install)", done: root.checks.sek === true, action: "I have it", run: [] },
              { id: "signin", label: "Sign in " + root.agent, done: root.chatState === "idle" || root.chatState === "working" || root.chatState === "blocked", action: "Sign in",
                run: ["xdg-terminal-exec", "--app-id=org.omanix.agent-login", "loom-agent-login", root.agent], disabled: root.checks.network !== true || root.checks.published === false },
              { id: "reviewer", label: "Sign in the reviewer (or skip: cards then show the diffs without an AI summary)", done: root.checks.reviewer === true, action: "Sign in",
                run: ["xdg-terminal-exec", "--app-id=org.omanix.agent-login", "loom-agent-login", "reviewer"], skip: true }
            ]
            Item {
              required property var modelData
              visible: modelData.id !== "signin" || root.chatState !== "none"
              width: parent.width
              height: visible ? Math.max(itemText.implicitHeight, Style.space(28)) : 0
              Text {
                id: itemText
                anchors { left: parent.left; right: buttons.left; verticalCenter: parent.verticalCenter; rightMargin: Style.space(8) }
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: (modelData.done ? "✓  " : "○  ") + modelData.label
                color: Commons.Color.popups.text
                opacity: modelData.done ? 0.6 : 1
                font.pixelSize: Style.font.body
              }
              Row {
                id: buttons
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: Style.space(6)
                visible: !modelData.done
                WelcomeButton { visible: modelData.action !== ""; text: modelData.action; enabled: modelData.disabled !== true
                  onClicked: modelData.run.length ? Quickshell.execDetached(modelData.run) : root.mark(modelData.id === "sek" ? "sek-written" : modelData.id) }
                WelcomeButton { visible: modelData.skip === true; text: "Skip"; onClicked: root.mark("reviewer") }
              }
            }
          }
        }

        Text {
          visible: root.slide >= 0
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.slide >= 0 ? root.tour[root.slide].text : ""
          color: Commons.Color.popups.text
          font.pixelSize: Style.font.body
        }

        Item {
          width: parent.width
          height: Style.space(30)
          Row {
            spacing: Style.space(6)
            WelcomeButton { visible: root.slide < 0; text: "Take the tour"; onClicked: root.slide = 0 }
            WelcomeButton { visible: root.slide >= 0; text: "Back"; onClicked: root.slide = root.slide - 1 }
          }
          Row {
            anchors.right: parent.right
            spacing: Style.space(6)
            WelcomeButton { visible: root.slide >= 0 && root.slide < root.tour.length - 1; text: "Next"; onClicked: root.slide = root.slide + 1 }
            WelcomeButton { text: root.slide < 0 ? "Done" : "Close"; primary: true; onClicked: root.dismiss() }
          }
        }
      }
    }
  }
}
