import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "CardModel.js" as CardModel

// omanix.approval (DESIGN §h.4): the cards for nuketown approval requests.
// omanix-approval-prompt (nuketown's prompter, K6) calls `show <request dir>`
// and waits for the decision this service writes to
// $XDG_RUNTIME_DIR/omanix-approval/<id>/decision.json. The card never takes
// the keyboard until the human clicks into it (U13), and it stands aside
// while a pinentry window is up, so it can't cover or steal a PIN prompt.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") + "/omanix-approval"
  readonly property string agent: Quickshell.env("OMANIX_AGENT_NAME") || "ada"
  readonly property string human: Quickshell.env("USER")

  // [{ id, dir, data: { request, review, card } | null }], oldest first.
  property var queue: []
  readonly property int pendingCount: queue.length
  readonly property var current: queue.length > 0 ? queue[0] : null
  readonly property var model: current && current.data && current.data.request
    ? CardModel.cardModel({ request: current.data.request, review: current.data.review, card: current.data.card,
        pendingIndex: 0, pendingTotal: queue.length, agent: root.agent, human: root.human })
    : null

  property bool expanded: false      // a routine banner opened into the full card
  property bool engaged: false       // the human clicked into the card: it has the keyboard
  property bool denyOpen: false
  property string detailPanel: ""    // "", "diff", "nvd", "info" (summary, can't see; a root card's command and script)
  property string detailText: ""
  property bool passwdOpen: false
  property var targets: ({})         // named controls, for geometry() (VM tests)

  // A pinentry (gpg's PIN prompt) or gcr prompt is up: stand aside.
  readonly property bool pinentryUp: {
    var list = ToplevelManager.toplevels.values
    for (var i = 0; i < list.length; i++) {
      var id = String(list[i].appId || "")
      if (/pinentry|gcr-prompter|org\.gnome\.keyring\.SystemPrompter/i.test(id)) return true
    }
    return false
  }
  readonly property bool cardShown: !!model && !pinentryUp && (model.form !== "routine" || expanded)
  readonly property bool bannerShown: !!model && !pinentryUp && model.form === "routine" && !expanded

  // Reset only for another request: reloading this one (the review landing)
  // updates the card in place, keeping an open reason field or details.
  readonly property string currentId: current ? current.id : ""
  onCurrentIdChanged: { expanded = false; engaged = false; denyOpen = false; detailPanel = ""; detailText = "" }
  onModelChanged: if (model && model.detailsOpen && detailPanel === "" && current) showDetail("info")

  function register(name, item, win) {
    var next = ({})
    for (var k in targets) next[k] = targets[k]
    next[name] = { item: item, win: win }
    targets = next
  }

  // ---- requests --------------------------------------------------------

  function validDir(dir) {
    return /^\/run\/nuketown-approval\/[A-Za-z0-9._-]+\/?$/.test(String(dir || ""))
  }

  function idOf(dir) {
    return String(dir).replace(/\/$/, "").split("/").pop()
  }

  function indexOf(id) {
    for (var i = 0; i < queue.length; i++) if (queue[i].id === id) return i
    return -1
  }

  function addRequest(dir) {
    if (!validDir(dir)) return "refused: not a request directory"
    var id = idOf(dir)
    if (indexOf(id) !== -1) return "ok"
    queue = queue.concat([{ id: id, dir: String(dir).replace(/\/$/, ""), data: null }])
    load(id)
    return "ok"
  }

  function removeRequest(id) {
    queue = queue.filter(function(e) { return e.id !== id })
  }

  function setData(id, data) {
    var next = queue.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i].id === id) next[i] = { id: next[i].id, dir: next[i].dir, data: data }
    }
    queue = next
  }

  function load(id) {
    var i = indexOf(id)
    if (i === -1) return
    loaderComponent.createObject(root, { entryId: id, command: ["bash", "-c", loadScript, "load", queue[i].dir] })
  }

  readonly property string loadScript: "cd \"$1\" || exit 1\n"
    + "v=null; [ -r review.json ] && v=$(cat review.json)\n"
    + "c=null; [ -r kind/card.json ] && c=$(cat kind/card.json)\n"
    + "jq -cn --slurpfile r request.json --argjson v \"$v\" --argjson c \"$c\" '{request: $r[0], review: $v, card: $c}' 2>/dev/null"
    + " || jq -cn --slurpfile r request.json '{request: $r[0], review: null, card: null}'"

  Component {
    id: loaderComponent
    Process {
      property string entryId: ""
      running: true
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          try { root.setData(entryId, JSON.parse(String(text || ""))) } catch (e) { console.warn("omanix.approval: unreadable request", entryId) }
        }
      }
      onExited: destroy()
    }
  }

  // review.json goes pending -> ok | unavailable while the card is up.
  Timer {
    interval: 1000
    repeat: true
    running: root.queue.some(function(e) { return !e.data || (e.data.review && e.data.review.status === "pending") })
    onTriggered: root.queue.forEach(function(e) { if (!e.data || (e.data.review && e.data.review.status === "pending")) root.load(e.id) })
  }

  // The prompter's marker: a card waiting on a decision survives a shell restart.
  Process {
    id: recoverProc
    running: true
    command: ["bash", "-c", "for d in \"$1\"/*/; do [ -r \"$d/dir\" ] && [ ! -e \"$d/decision.json\" ] && head -n1 \"$d/dir\"; done; true", "recover", root.runtimeDir]
    stdout: SplitParser { onRead: function(line) { root.addRequest(String(line).trim()) } }
  }

  function decide(decision, reason) {
    if (!current) return
    var id = current.id
    var payload = JSON.stringify({ decision: decision, reason: String(reason || "").replace(/[\u0000-\u001f]/g, " ").slice(0, 500) })
    writeComponent.createObject(root, { command: ["bash", "-c",
      "umask 077; mkdir -p \"$1\" && printf '%s\\n' \"$2\" > \"$1/decision.json.tmp\" && mv -f \"$1/decision.json.tmp\" \"$1/decision.json\"",
      "decide", root.runtimeDir + "/" + id, payload] })
    removeRequest(id)
  }

  Component {
    id: writeComponent
    Process { running: true; onExited: destroy() }
  }

  // ---- details ---------------------------------------------------------

  function showDetail(which) {
    if (!current) return
    if (detailPanel === which) { detailPanel = ""; return }
    detailPanel = which
    detailText = ""
    var dir = current.dir
    if (which === "info" && model && model.kind !== "root") return   // the review's details only
    var script = which === "diff" ? "cat \"$1/kind/stat.txt\"; echo; head -c 204800 \"$1/kind/diff.txt\""
      : which === "nvd" ? "head -c 204800 \"$1/kind/nvd.txt\""
      : "jq -r '.snapshots[] | [.snapshot, .path, .sha256, (if .executed then \"runs\" else \"review only\" end)] | @tsv' \"$1/request.json\" | "
        + "while IFS=$'\\t' read -r snap path sha how; do case $snap in snapshots/*) ;; *) continue ;; esac; "
        + "printf '==== %s (%s)\\n==== sha256 %s\\n' \"$path\" \"$how\" \"$sha\"; head -c 1048576 \"$1/$snap\" | cat -n; echo; done"
    detailProc.command = ["bash", "-c", script, "detail", dir]
    detailProc.running = true
  }

  Process {
    id: detailProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.detailText = String(text || "") }
  }

  // ---- IPC (omarchy-shell omanix.approval …) ----------------------------

  ShellIpc {
    target: "omanix.approval"

    function show(dir: string): string { return root.addRequest(dir) }
    function dismiss(id: string): void { root.removeRequest(id) }
    function open(): void {
      if (root.current) { root.expanded = true; root.engaged = true }
      else Util.execArgv(["omarchy-notification-send", "-u", "low", "No approvals waiting", "Cards for " + root.agent + "'s changes show up here."])
    }
    function openUpdate(): void {
      for (var i = 0; i < root.queue.length; i++) {
        var d = root.queue[i].data
        if (d && d.card && d.card.kind === "update") {
          var e = root.queue[i]
          root.queue = [e].concat(root.queue.filter(function(x) { return x.id !== e.id }))
          root.expanded = true
          return
        }
      }
      Util.execArgv(["omarchy-notification-send", "-u", "low", "No update card waiting", "The update check runs daily; the menu's Update › Check for updates runs it now."])
    }
    function passwd(): void { root.passwdOpen = true }
    function pending(): int { return root.pendingCount }
    function ping(): string { return "ok" }
    function state(): string {
      return JSON.stringify({ pending: root.pendingCount, current: root.current ? root.current.id : "",
        form: root.model ? root.model.form : "", shown: root.cardShown ? "card" : (root.bannerShown ? "banner" : "none"),
        engaged: root.engaged, pinentry: root.pinentryUp, detail: root.detailPanel, denyOpen: root.denyOpen,
        approveLabel: root.model ? root.model.approveLabel : "",
        review: root.model ? root.model.review.state : "", headline: root.model ? root.model.review.headline : "",
        reason: reasonField.text })
    }
    // Screen coordinates of a named control's center (VM tests drive clicks).
    function geometry(name: string): string {
      var t = root.targets[name]
      if (!t || !t.item || !t.item.visible) return ""
      var banner = t.win === "banner"
      var win = banner ? bannerWindow : cardWindow
      if (!win.visible || !win.screen) return ""
      var p = t.item.mapToItem(null, t.item.width / 2, t.item.height / 2)
      var ox = banner ? win.screen.width - win.width - win.margins.right : Math.round((win.screen.width - win.width) / 2)
      var oy = banner ? win.margins.top : Math.round((win.screen.height - win.height) / 2)
      return Math.round(ox + p.x) + " " + Math.round(oy + p.y)
    }
  }

  // ---- surfaces --------------------------------------------------------

  readonly property color fg: Commons.Color.popups.text
  readonly property color bg: Commons.Color.popups.background
  readonly property string mono: Style.font.family

  // Routine form: one line, top-right, never focused (§h.4).
  PanelWindow {
    id: bannerWindow
    visible: root.bannerShown
    anchors { top: true; right: true }
    margins { top: Style.space(40); right: Style.space(12) }
    implicitWidth: Math.min(Style.space(560), bannerRow.implicitWidth + Style.space(24))
    implicitHeight: bannerRow.implicitHeight + Style.space(16)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omanix-approval-banner"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: Commons.Color.notifications.background
      border.width: 1
      border.color: Commons.Color.notifications.border

      Row {
        id: bannerRow
        anchors.centerIn: parent
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, Style.space(300))
          elide: Text.ElideRight
          textFormat: Text.PlainText
          color: Commons.Color.notifications.text
          font.family: root.mono
          font.pixelSize: Style.font.body
          text: root.model && root.model.banner ? root.model.banner.icon + "  " + root.model.banner.quote
            + (root.model.banner.packages ? "  ·  " + root.model.banner.packages : "") + "  ·  " + root.model.banner.reviewer : ""
        }
        CardButton { id: bDetails; text: "Details"; onClicked: root.expanded = true; Component.onCompleted: root.register("banner.details", bDetails, "banner") }
        CardButton { id: bApprove; text: root.model ? root.model.approveLabel : "Approve"; primary: true; onClicked: root.decide("approve", ""); Component.onCompleted: root.register("banner.approve", bApprove, "banner") }
        CardButton { id: bDeny; text: "✕"; onClicked: root.decide("deny", ""); Component.onCompleted: root.register("banner.deny", bDeny, "banner") }
      }
    }
  }

  // Full change card and root-command card: centered, 720 px. Keyboard only
  // after a click into it (Exclusive from then on, so the reason field gets
  // what is typed); Escape or the decision hands focus back.
  PanelWindow {
    id: cardWindow
    visible: root.cardShown
    implicitWidth: Style.space(720)
    implicitHeight: Math.min(cardColumn.implicitHeight + Style.space(32), (screen ? screen.height : 900) - Style.space(80))
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omanix-approval"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.engaged ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onVisibleChanged: if (!visible) root.engaged = false

    Rectangle {
      id: cardFrame
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.bg
      border.width: Math.max(1, Style.space(2))
      border.color: Commons.Color.popups.border
      focus: true

      Keys.onEscapePressed: { root.denyOpen = false; root.engaged = false }

      Flickable {
        id: cardFlick
        anchors.fill: parent
        anchors.margins: Style.space(16)
        contentWidth: width
        contentHeight: cardColumn.implicitHeight
        clip: true

        Column {
          id: cardColumn
          width: cardFlick.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            height: titleText.implicitHeight
            Text {
              id: titleText
              textFormat: Text.PlainText
              text: root.model ? root.model.title : ""
              color: root.fg
              font.family: root.mono
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.model ? root.model.pendingText : ""
              color: Util.alpha(root.fg, 0.6)
              font.family: root.mono
              font.pixelSize: Style.font.bodySmall
            }
          }

          // A root card's command, as the reviewer and the details see it.
          Text {
            visible: !!root.model && root.model.kind === "root"
            width: parent.width
            leftPadding: Style.space(12)
            maximumLineCount: 3
            elide: Text.ElideRight
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
            text: root.model && root.model.command ? root.model.command.display : ""
            color: root.fg
            font.family: root.mono
            font.pixelSize: Style.font.body
          }

          Text {
            textFormat: Text.PlainText
            text: root.model ? root.model.requestHeading : ""
            color: Util.alpha(root.fg, 0.65)
            font.family: root.mono
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.model ? root.model.requestText : ""
            color: root.fg
            font.family: root.mono
            font.pixelSize: Style.font.subtitle
          }

          Column {
            visible: !!root.model && root.model.kind === "change"
            width: parent.width
            spacing: Style.space(4)
            Text {
              textFormat: Text.PlainText
              text: "WHAT CHANGES"
              color: Util.alpha(root.fg, 0.65)
              font.family: root.mono
              font.pixelSize: Style.font.caption
              font.bold: true
            }
            Repeater {
              model: root.model && root.model.changes ? root.model.changes : []
              Text {
                required property var modelData
                width: cardColumn.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: modelData.label + "   " + modelData.text
                color: modelData.warn ? Commons.Color.urgent : root.fg
                font.family: root.mono
                font.pixelSize: Style.font.body
              }
            }
          }

          // The review (§h.4), labelled as fallible: a risk badge, the
          // recommendation as a word and the reviewer's headline, then its
          // concerns. The summary and "Can't see" are details (ⓘ). A pending
          // review is a spinner line; the card updates in place when it lands.
          Rectangle {
            width: parent.width
            height: reviewColumn.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Util.alpha(Commons.Color.accent, 0.10)
            Column {
              id: reviewColumn
              x: Style.space(8)
              y: Style.space(8)
              width: parent.width - Style.space(16)
              spacing: Style.space(4)
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: root.model ? root.model.review.heading : ""
                color: root.model && root.model.review.state === "none" ? Commons.Color.urgent : Util.alpha(root.fg, 0.75)
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Item {
                id: reviewLine
                visible: !!root.model && root.model.review.state !== "none"
                width: parent.width
                height: Math.max(headlineText.implicitHeight, riskBadge.visible ? riskBadge.height : 0, busy.visible ? busy.height : 0)
                readonly property string risk: root.model ? root.model.review.risk : ""
                Rectangle {
                  id: riskBadge
                  visible: !!root.model && root.model.review.state === "ok"
                  width: visible ? badgeText.implicitWidth + Style.space(12) : 0
                  height: badgeText.implicitHeight + Style.space(4)
                  radius: Style.space(4)
                  color: reviewLine.risk === "high" ? Commons.Color.urgent
                    : reviewLine.risk === "medium" ? "#b7791f"
                    : reviewLine.risk === "low" ? "#3f7f4f" : Commons.Color.muted
                  Text {
                    id: badgeText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: root.model ? root.model.review.badge : ""
                    color: "#ffffff"
                    font.family: root.mono
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
                BusyIndicator {
                  id: busy
                  visible: !!root.model && root.model.review.state === "pending"
                  running: visible
                  width: visible ? Style.space(20) : 0
                  height: Style.space(20)
                }
                Text {
                  id: headlineText
                  x: (riskBadge.visible ? riskBadge.width : 0) + (busy.visible ? busy.width : 0) + Style.space(8)
                  width: parent.width - x
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: root.model ? (root.model.review.state === "ok" ? root.model.review.recWord + " · " : "") + root.model.review.headline : ""
                  color: root.fg
                  font.pixelSize: Style.font.body
                  font.bold: !!root.model && root.model.review.state === "ok"
                }
              }
              Repeater {
                model: root.model ? root.model.review.notes : []
                Text {
                  required property var modelData
                  width: reviewColumn.width
                  leftPadding: Style.space(12)
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: "• " + modelData
                  color: root.fg
                  font.italic: true
                  font.pixelSize: Style.font.body
                }
              }
            }
          }

          // ⓘ: the details, in place.
          Item {
            width: parent.width
            height: infoButton.implicitHeight
            CardButton {
              id: infoButton
              anchors.right: parent.right
              text: "i"
              round: true
              ToolTip.visible: hovered
              ToolTip.text: "Details"
              onClicked: root.showDetail("info")
              Component.onCompleted: root.register("card.info", infoButton, "card")
            }
          }

          Rectangle {
            visible: root.detailPanel !== ""
            width: parent.width
            height: Math.min(Style.space(320), detailBody.implicitHeight + Style.space(12))
            color: Util.alpha(root.fg, 0.04)
            radius: Style.cornerRadius
            ScrollView {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              clip: true
              Column {
                id: detailBody
                spacing: 0
                Text {
                  visible: root.detailPanel === "info" && !!root.model && root.model.review.state !== "none"
                  width: cardColumn.width - Style.space(24)
                  wrapMode: Text.Wrap
                  textFormat: Text.PlainText
                  text: root.model
                    ? root.model.review.summary + (root.model.review.state === "ok" ? "\nCan't see: " + CardModel.cantSee(root.model.review.notShown) : "") + "\n"
                    : ""
                  color: root.fg
                  font.italic: true
                  font.pixelSize: Style.font.body
                }
                Text {
                  visible: root.detailPanel === "info" && !!root.model && !!root.model.command
                  textFormat: Text.PlainText
                  text: root.model && root.model.command
                    ? "runs as " + root.model.command.runAs + ":\n" + root.model.command.argv.map(function(a, i) { return "  argv[" + i + "] " + a }).join("\n")
                      + (root.model.command.decrypt.length ? "\nalso decrypts: " + root.model.command.decrypt.join(", ") : "") + "\n"
                    : ""
                  color: root.fg
                  font.family: root.mono
                  font.pixelSize: Style.font.bodySmall
                }
                Repeater {
                  model: root.detailText.split("\n")
                  Text {
                    required property string modelData
                    textFormat: Text.PlainText
                    text: modelData
                    color: root.detailPanel === "diff" && /^\+/.test(modelData) && !/^\+\+\+/.test(modelData) ? "#7fbf7f"
                      : root.detailPanel === "diff" && /^-/.test(modelData) && !/^---/.test(modelData) ? "#d07070"
                      : /^(@@|====)/.test(modelData) ? Commons.Color.accent : root.fg
                    font.family: root.mono
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          // Deny's optional reason, in the card: Enter (or Deny again) sends
          // it, Escape goes back and hands the keyboard back.
          Column {
            visible: root.denyOpen
            width: parent.width
            spacing: Style.space(4)
            TextField {
              id: reasonField
              width: parent.width
              placeholderText: "Reason (optional; " + root.agent + " sees it as your reply)"
              maximumLength: 500
              color: root.fg
              font.family: root.mono
              onAccepted: root.decide("deny", text)
              Component.onCompleted: root.register("card.reason", reasonField, "card")
            }
            Text {
              textFormat: Text.PlainText
              text: "Enter denies with this reason · Escape goes back"
              color: Util.alpha(root.fg, 0.6)
              font.pixelSize: Style.font.caption
            }
          }

          Item {
            width: parent.width
            height: rightButtons.implicitHeight
            Row {
              spacing: Style.space(8)
              Repeater {
                model: root.model ? root.model.buttons : []
                CardButton {
                  id: detailButton
                  required property var modelData
                  text: modelData.label
                  onClicked: root.showDetail(modelData.id)
                  Component.onCompleted: root.register("card." + modelData.id, detailButton, "card")
                }
              }
            }
            Row {
              id: rightButtons
              anchors.right: parent.right
              spacing: Style.space(8)
              CardButton {
                text: root.model ? root.model.denyLabel : "Deny"
                id: cDeny
                warn: root.denyOpen
                onClicked: {
                  if (root.denyOpen) { root.decide("deny", reasonField.text); return }
                  root.engaged = true; root.denyOpen = true; reasonField.text = ""; reasonField.forceActiveFocus()
                }
                Component.onCompleted: root.register("card.deny", cDeny, "card")
              }
              CardButton {
                text: root.model ? root.model.approveLabel : "Approve"
                primary: true
                warn: !!root.model && root.model.approveLabel !== "Approve"
                id: cApprove
                onClicked: root.decide("approve", "")
                Component.onCompleted: root.register("card.approve", cApprove, "card")
              }
            }
          }
        }
      }

      // A press anywhere on the card is the human choosing to use it; the
      // press still reaches the control under it. The keyboard is taken a
      // moment later: Hyprland releases every mouse button when a layer turns
      // exclusive, which would cancel the click in progress.
      MouseArea {
        anchors.fill: parent
        onPressed: function(mouse) { engageTimer.restart(); mouse.accepted = false }
      }
      Timer { id: engageTimer; interval: 250; onTriggered: if (root.cardShown) root.engaged = true }
    }
  }

  PasswdDialog {
    shown: root.passwdOpen
    onDismissed: root.passwdOpen = false
  }
}
