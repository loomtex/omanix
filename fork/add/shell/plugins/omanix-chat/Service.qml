import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ChatModel.js" as ChatModel

// omanix.chat (DESIGN §h.3): the connection to the resident's bridge
// (/run/loom/chat/<agent>.sock, loom.chat/v1, newline-delimited JSON) and the
// conversation state the panel and the bar widget draw. Always loaded, so
// the transcript and the reconnect survive the panel closing (U10).
Item {
  id: root
  visible: false

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // /etc/omanix/chat.json (modules/omanix/chat.nix).
  property var config: ({})
  readonly property bool agentEnabled: config.agent !== undefined && config.agent !== ""
  readonly property string agent: config.agent || Quickshell.env("OMANIX_AGENT_NAME") || "ada"
  readonly property string socketPath: config.socket || ("/run/loom/chat/" + agent + ".sock")
  readonly property int maxBytes: config.maxBytes || 8388608

  // Connection.
  property bool connected: false
  property bool detached: false          // another surface took the socket
  property string boot: ""
  property int lastSeq: 0
  property string sessionId: ""
  property string agentStatus: "offline" // idle | working | blocked | offline | signed-out
  property int questions: 0               // unanswered questions (bar: needs you)
  readonly property string chatState: !agentEnabled ? "none" : (!connected ? "offline" : agentStatus)

  // Composer and views.
  property string composerText: ""
  property string source: ""              // "from menu: Defaults › Browser › Firefox"
  property string sourceId: ""
  property string view: "chat"            // chat | options | agent | diy
  property var diy: null                  // the intent row a Do-it-yourself view explains
  property var chips: []
  property var facts: ({})
  property var rules: ({})
  property var attachments: []            // [{ ref, name, size, kind, path, preview, id, error }]
  property var intents: ({})
  property bool bubbleOpen: false

  ListModel { id: transcriptModel }
  readonly property var transcript: transcriptModel

  signal composerFocusRequested()

  FileView {
    path: "/etc/omanix/chat.json"
    printErrors: false
    onLoaded: { try { root.config = JSON.parse(text()) } catch (e) { root.config = ({}) } }
  }
  FileView {
    path: "/etc/omanix/chips/rules.json"
    printErrors: false
    onLoaded: { try { root.rules = JSON.parse(text()) } catch (e) { root.rules = ({}) } }
  }
  FileView {
    path: root.omarchyPath + "/default/omanix/intents.json"
    printErrors: false
    onLoaded: { try { root.intents = JSON.parse(text()) } catch (e) { root.intents = ({}) } }
  }

  // ---- the socket ------------------------------------------------------

  Socket {
    id: sock
    path: root.socketPath
    connected: false
    parser: SplitParser {
      onRead: function(line) { root.receive(line) }
    }
    onConnectionStateChanged: {
      root.connected = sock.connected
      if (!sock.connected) root.bubbleOpen = false
    }
    onError: function(error) { root.connected = false }
  }

  // Reconnect (bridge restart, first boot before repo-publish): every 2 s,
  // unless another surface took over (then only when the panel opens).
  Timer {
    interval: 2000
    repeat: true
    running: root.agentEnabled && !root.connected && !root.detached
    triggeredOnStart: true
    onTriggered: { sock.connected = false; sock.connected = true }
  }

  function send(obj) {
    if (!sock.connected) return false
    sock.write(JSON.stringify(obj) + "\n")
    sock.flush()
    return true
  }

  function add(kind, text, detail, data) {
    transcriptModel.append({ kind: kind, text: String(text || ""), detail: String(detail || ""),
      payload: JSON.stringify(data || {}) })
  }

  function receive(line) {
    var e
    try { e = JSON.parse(line) } catch (x) { return }
    if (!e || typeof e.t !== "string") return
    if (e.t === "hello") {
      agentStatus = String(e.status || "idle")
      if (e.session) sessionId = String(e.session)
      if (boot !== "" && e.boot === boot) send({ t: "sync", boot: boot, since: lastSeq })
      else { boot = String(e.boot || ""); send({ t: "sync", boot: "", since: 0 }) }
      return
    }
    if (e.t === "detached") { detached = true; return }
    if (e.t === "reset") { transcriptModel.clear(); lastSeq = 0; bubbleOpen = false; questions = 0; return }
    if (typeof e.seq === "number") {
      if (e.seq <= lastSeq) return
      lastSeq = e.seq
    }
    switch (e.t) {
    case "session": sessionId = String(e.id || ""); break
    case "text":
      if (bubbleOpen && transcriptModel.count > 0 && transcriptModel.get(transcriptModel.count - 1).kind === "agent") {
        var last = transcriptModel.count - 1
        transcriptModel.setProperty(last, "text", transcriptModel.get(last).text + String(e.delta || ""))
      } else {
        add("agent", e.delta)
        bubbleOpen = true
      }
      break
    case "activity": bubbleOpen = false; add("activity", ChatModel.activityLabel(e), e.kind, { external: e.external === true }); break
    case "progress":
      for (var i = transcriptModel.count - 1; i >= 0 && i >= transcriptModel.count - 5; i--) {
        if (transcriptModel.get(i).kind === "progress") { transcriptModel.setProperty(i, "text", ChatModel.progressLabel(e)); return }
      }
      bubbleOpen = false; add("progress", ChatModel.progressLabel(e)); break
    case "card": bubbleOpen = false; add("card", "Approval card opened", "", { id: e.id }); break
    case "question": bubbleOpen = false; questions++; add("question", e.text, "", { choices: e.choices || [] }); break
    case "status": agentStatus = String(e.status || "idle"); break
    case "auth":
      if (/^https:\/\//.test(String(e.url || ""))) { bubbleOpen = false; add("auth", ChatModel.domainOf(e.url), "", { url: e.url }) }
      break
    case "rejected": bubbleOpen = false; add("notice", "You rejected " + String(e.tip || "").slice(0, 12) + ": " + String(e.reason || "")); break
    case "applied": bubbleOpen = false; add("applied", "Applied: " + String(e.tip || "").slice(0, 12), e.check); break
    case "rolledback": bubbleOpen = false; add("rolledback", "Rolled back: " + String(e.check || "a health check failed"), e.tip); break
    case "error": bubbleOpen = false; add("error", e.text); break
    case "attached": attachmentDone(String(e.ref || ""), String(e.id || ""), ""); break
    case "attach-rejected": attachmentDone(String(e.ref || ""), "", String(e.reason || "refused")); break
    }
  }

  // ---- sending ---------------------------------------------------------

  property var outgoing: null   // { text, refs } waiting for attachments

  function submit() {
    var text = composerText.trim()
    if (text === "" && attachments.length === 0) return
    if (!connected) { add("error", root.agent + " isn't connected; nothing was sent."); return }
    bubbleOpen = false
    add("human", text, source)
    composerText = ""
    source = ""
    sourceId = ""
    questions = 0
    if (attachments.length === 0) { send({ t: "user", text: text }); return }
    outgoing = { text: text }
    attachments.forEach(function(a) { uploadComponent.createObject(root, { att: a }) })
  }

  function attachmentDone(ref, id, error) {
    var next = attachments.map(function(a) {
      return a.ref === ref ? { ref: a.ref, name: a.name, size: a.size, kind: a.kind, path: a.path, preview: a.preview, id: id, error: error } : a
    })
    attachments = next
    if (!outgoing) return
    if (next.some(function(a) { return a.id === "" && a.error === "" })) return
    var ids = next.filter(function(a) { return a.id !== "" }).map(function(a) { return a.id })
    next.filter(function(a) { return a.error !== "" }).forEach(function(a) { add("error", a.name + " was not sent: " + a.error) })
    send({ t: "user", text: outgoing.text, attachments: ids })
    outgoing = null
    attachments = []
  }

  // One upload: base64 of the file, in chunks of ≤ 256 KiB decoded.
  Component {
    id: uploadComponent
    Process {
      property var att
      running: true
      command: ["base64", "-w0", "--", att.path]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var b = String(text || "")
          root.send({ t: "attach-begin", ref: att.ref, name: att.name, size: att.size })
          for (var i = 0; i < b.length; i += 262144) root.send({ t: "attach-chunk", ref: att.ref, data: b.slice(i, i + 262144) })
          root.send({ t: "attach-end", ref: att.ref })
        }
      }
      onExited: destroy()
    }
  }

  // Attach: the human hands context over explicitly, with a preview (§h.3.5).
  function attach(kind, arg) {
    var ref = "a" + Date.now()
    var script = kind === "file" ? "f=$(zenity --file-selection 2>/dev/null) || exit 1; printf '%s' \"$f\""
      : kind === "clipboard" ? "t=$(mktemp --suffix=.txt); wl-paste --no-newline --type text/plain > \"$t\" || exit 1; printf '%s' \"$t\""
      : kind === "screenshot" ? "t=$(mktemp --suffix=.png); g=$(slurp) || exit 1; grim -g \"$g\" \"$t\" || exit 1; printf '%s' \"$t\""
      : "t=$(mktemp --suffix=.json); omanix-runtime-snapshot \"$1\" > \"$t\" || exit 1; printf '%s' \"$t\""
    pickComponent.createObject(root, { ref: ref, kind: kind, command: ["bash", "-c", script, "attach", String(arg || "look")] })
  }

  Component {
    id: pickComponent
    Process {
      property string ref
      property string kind
      running: true
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var p = String(text || "").trim()
          if (p !== "") root.previewAttachment(ref, kind, p)
        }
      }
      onExited: destroy()
    }
  }

  function previewAttachment(ref, kind, path) {
    previewComponent.createObject(root, { ref: ref, kind: kind, path: path,
      command: ["bash", "-c", "f=$1; s=$(stat -c %s -- \"$f\") || exit 1; t=$(file -b --mime-type -- \"$f\"); printf '%s\\t%s\\n' \"$s\" \"$t\"; case $t in text/*|application/json) head -c 400 -- \"$f\";; esac", "preview", path] })
  }

  Component {
    id: previewComponent
    Process {
      property string ref
      property string kind
      property string path
      running: true
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var out = String(text || "")
          var nl = out.indexOf("\n")
          var head = (nl < 0 ? out : out.slice(0, nl)).split("\t")
          var size = parseInt(head[0]) || 0
          var type = head[1] || ""
          var name = path.split("/").pop()
          var error = ""
          if (["image/png", "image/jpeg", "text/plain", "application/json"].indexOf(type) === -1 && !/^text\//.test(type)) error = "only PNG, JPEG, text and JSON can be attached"
          else if (size > root.maxBytes) error = "larger than " + Math.round(root.maxBytes / 1048576) + " MiB"
          if (error !== "") { root.add("error", name + ": " + error); return }
          root.attachments = root.attachments.concat([{ ref: ref, name: name, size: size, kind: type, path: path,
            preview: nl < 0 ? "" : out.slice(nl + 1), id: "", error: "" }])
        }
      }
      onExited: destroy()
    }
  }

  function removeAttachment(ref) { attachments = attachments.filter(function(a) { return a.ref !== ref }) }

  // ---- facts for the chips (local state only) --------------------------

  Process {
    id: factsProc
    command: ["omanix-chat-facts"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.facts = JSON.parse(String(text || "{}")) } catch (e) { root.facts = ({}) } }
    }
  }
  onFactsChanged: chips = ChatModel.chips(rules, facts, agent)
  onRulesChanged: chips = ChatModel.chips(rules, facts, agent)
  function refreshFacts() { if (!factsProc.running) factsProc.running = true }

  // ---- what the menu, keybindings and other plugins call ----------------

  function isOpen() { return root.shell ? root.shell.isPluginOpen("omanix.chat") : false }
  function openPanel() {
    if (detached) { detached = false }
    refreshFacts()
    if (root.shell) root.shell.summon("omanix.chat", "{}")
    composerFocusRequested()
  }

  function prefill(payload) {
    var p = payload || {}
    var text = String(p.text || "")
    composerText = text
    sourceId = String(p.id || "")
    source = p.path ? "from " + String(p.source || "menu") + ": " + String(p.path) : (p.source ? "from " + String(p.source) : "")
    diy = p.id && intents[p.id] ? { id: p.id, label: intents[p.id].label, text: text, manual: intents[p.id].manual, skill: intents[p.id].skill } : null
    // No agent to ask: the row's how-to instead (§h.5.3 step 7).
    view = (chatState === "none" || chatState === "offline" || chatState === "signed-out") && diy ? "diy" : "chat"
    openPanel()
  }

  function intent(id) {
    var row = intents[id]
    if (!row) return "unknown intent " + id
    prefill({ source: "keybinding", id: id, text: ChatModel.renderIntent(row.text, { label: row.label }), skill: row.skill, path: row.label })
    return "ok"
  }

  ShellIpc {
    target: "omanix.chat"

    function toggle(): void { if (root.isOpen()) root.shell.hide("omanix.chat"); else { root.view = "chat"; root.openPanel() } }
    function open(): void { root.view = "chat"; root.openPanel() }
    function close(): void { if (root.shell) root.shell.hide("omanix.chat") }
    function prefill(json: string): string {
      var p
      try { p = JSON.parse(json) } catch (e) { return "bad json" }
      root.prefill(p)
      return "ok"
    }
    function intent(id: string): string { return root.intent(id) }
    function whatCanIChange(): void { root.view = "options"; root.openPanel() }
    function agent(): void { root.view = "agent"; root.openPanel() }
    function makeItStick(area: string): void {
      root.prefill({ source: "make it stick", id: "appearance.make-it-stick", text: "Make my current " + area + " settings permanent.", skill: "look" })
      root.attach("snapshot", area)
    }
    function ping(): string { return "ok" }
    function status(): string { return root.chatState }
    // For tests and omanix.status: no conversation text, only state.
    function state(): string {
      return JSON.stringify({ connected: root.connected, detached: root.detached, boot: root.boot, lastSeq: root.lastSeq,
        status: root.chatState, view: root.view, open: root.isOpen(), composer: root.composerText, source: root.source,
        items: root.transcript.count, attachments: root.attachments.length, chips: root.chips.map(function(c) { return c.label }) })
    }
  }
}
