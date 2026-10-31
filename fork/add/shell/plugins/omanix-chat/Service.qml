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

  // Agent-requested previews (§h.6): the latest one, for the panel and tests.
  // state: checking | asked | refused | applying | previewing | kept | reverted | declined
  property var preview: null

  // The options browser (§h.6): `omanix options` over the catalogs, and the
  // current values from the running system's config.json.
  property string optionsQuery: ""
  property var optionsResults: []
  property int optionsTotal: 0
  property bool optionsBusy: false
  property var currentConfig: ({})

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
    path: "/run/current-system/catalog/config.json"
    printErrors: false
    onLoaded: { try { root.currentConfig = JSON.parse(text()) } catch (e) { root.currentConfig = ({}) } }
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

  // Tests and the demo: the kinds of the last rows, and the activity rail's
  // labels and notices (never what the human or the agent wrote).
  function rowSummary() {
    var out = []
    for (var i = Math.max(0, transcriptModel.count - 60); i < transcriptModel.count; i++) {
      var r = transcriptModel.get(i)
      out.push(r.kind === "activity" || r.kind === "applied" || r.kind === "rolledback" || r.kind === "notice" || r.kind === "preview" || r.kind === "error"
        ? { kind: r.kind, text: r.text } : { kind: r.kind })
    }
    return out
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
    case "preview-request": bubbleOpen = false; previewRequested(e); break
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
      // the type from the name, text checked with grep -I (no file(1) on a
      // default system)
      command: ["bash", "-c", "f=$1; s=$(stat -c %s -- \"$f\") || exit 1; "
        + "case ${f,,} in *.png) t=image/png;; *.jpg|*.jpeg) t=image/jpeg;; *.json) t=application/json;; "
        + "*) if [ ! -s \"$f\" ] || grep -Iq . -- \"$f\"; then t=text/plain; else t=application/octet-stream; fi;; esac; "
        + "printf '%s\\t%s\\n' \"$s\" \"$t\"; case $t in text/*|application/json) head -c 400 -- \"$f\";; esac", "preview", path] })
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

  // ---- agent-requested previews (§h.6) -----------------------------------
  // The resident has no Wayland access: `omanix try` reaches us as data
  // ({path, value} or {reset}). omanix-preview (the human-session helper)
  // checks it against catalog/preview.json and renders the change itself;
  // the row shows its rendering, never text from the request. Allow applies
  // it; Keep leaves it as runtime state (Make it stick from there); Revert,
  // or closing the panel while it's still a preview, undoes it.

  function previewRequested(e) {
    if (e.reset === true) {
      if (preview && (preview.state === "previewing")) previewRun("reset", [], "reverted")
      add("notice", root.agent + " reverted its preview")
      return
    }
    var p = { id: "p" + Date.now(), path: String(e.path || ""), value: e.value, label: "", state: "checking", reason: "" }
    preview = p
    add("preview", "", "checking", { id: p.id })
    previewRun("check", [p.path, JSON.stringify(p.value)], "asked")
  }

  function setPreview(changes) {
    if (!preview) return
    var n = {}
    for (var k in preview) n[k] = preview[k]
    for (var c in changes) n[c] = changes[c]
    preview = n
    for (var i = transcriptModel.count - 1; i >= 0; i--) {
      var row = transcriptModel.get(i)
      if (row.kind === "preview" && JSON.parse(row.payload).id === n.id) {
        transcriptModel.setProperty(i, "text", n.label || n.reason)
        transcriptModel.setProperty(i, "detail", n.state)
        break
      }
    }
  }

  // verb: check | apply | reset; next: the state on success
  function previewRun(verb, args, next) {
    previewComponent2.createObject(root, { verb: verb, next: next, command: ["omanix-preview", verb].concat(args) })
  }

  Component {
    id: previewComponent2
    Process {
      property string verb
      property string next
      running: true
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var r
          try { r = JSON.parse(String(text || "{}")) } catch (e) { r = { ok: false, refused: "the preview helper didn't answer" } }
          if (verb === "reset") { root.setPreview({ state: next }); return }
          if (r.ok) root.setPreview({ state: next, label: String(r.label || "") })
          else root.setPreview({ state: verb === "check" ? "refused" : "failed", reason: String(r.refused || "refused") })
        }
      }
      onExited: destroy()
    }
  }

  // Undo the last change: `loom undo` as the human (polkit farm.loom.undo in
  // the active session), which raises the routine "Undo: …" card.
  // A refusal (nothing to undo, the old system was collected) is an error
  // row with loom's own words, not silence.
  function undoLast() { undoComponent.createObject(root, {}) }

  Component {
    id: undoComponent
    Process {
      running: true
      command: ["bash", "-c", "out=$(loom undo 2>&1 </dev/null); rc=$?; printf '%s\\n%s' \"$rc\" \"$out\""]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var out = String(text || "")
          var nl = out.indexOf("\n")
          var rc = parseInt(nl < 0 ? out : out.slice(0, nl))
          var msg = (nl < 0 ? "" : out.slice(nl + 1)).trim().split("\n").filter(function(l) { return l.trim() !== "" }).pop() || ""
          if (rc !== 0) root.add("error", "Undo didn't go through: " + (msg || "loom undo exited " + rc))
        }
      }
      onExited: destroy()
    }
  }

  // The panel closed: a preview nobody kept goes back.
  function panelClosed() {
    if (preview && preview.state === "previewing") previewRun("reset", [], "reverted")
  }

  // Allow | Not now | Keep | Revert, on the latest request.
  function previewAnswer(action) {
    if (!preview) return "no preview"
    var st = preview.state
    if (action === "allow" && st === "asked") { setPreview({ state: "applying" }); previewRun("apply", [preview.path, JSON.stringify(preview.value)], "previewing") }
    else if (action === "notnow" && st === "asked") setPreview({ state: "declined" })
    else if (action === "keep" && st === "previewing") setPreview({ state: "kept" })
    else if (action === "revert" && st === "previewing") previewRun("reset", [], "reverted")
    else return "not now (" + st + ")"
    return "ok"
  }

  // ---- options browser ---------------------------------------------------

  function currentValue(path) {
    var v = currentConfig
    var parts = String(path).split(".")
    for (var i = 0; i < parts.length; i++) {
      if (v === null || typeof v !== "object" || !(parts[i] in v)) return undefined
      v = v[parts[i]]
    }
    return v
  }

  Timer { id: optionsDebounce; interval: 350; onTriggered: root.searchOptionsNow() }
  onOptionsQueryChanged: optionsDebounce.restart()

  function searchOptionsNow() {
    var words = optionsQuery.trim().split(/\s+/).filter(function(w) { return w.length > 0 && w.charAt(0) !== "-" })
    if (words.join("").length < 2) { optionsResults = []; optionsTotal = 0; return }
    if (optionsProc.running) optionsProc.running = false
    optionsProc.command = ["omanix", "options", "--json", "--limit", "40"].concat(words)
    optionsBusy = true
    optionsProc.running = true
  }

  Process {
    id: optionsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.optionsBusy = false
        var r
        try { r = JSON.parse(String(text || "{}")) } catch (e) { r = {} }
        root.optionsResults = (r.results || []).map(function(o) {
          var cur = root.currentValue(o.path)
          return { path: String(o.path), type: String(o.type || ""), origin: String(o.origin || ""),
            description: String(o.description || ""), current: cur === undefined ? "" : JSON.stringify(cur),
            hasCurrent: cur !== undefined, def: o["default"] === undefined || o["default"] === null ? "" : String(typeof o["default"] === "string" ? o["default"] : JSON.stringify(o["default"])) }
        })
        root.optionsTotal = r.total || 0
      }
    }
  }

  // "Ask ada to change it": a pre-filled, unsent request.
  function askToChange(o) {
    var from = o.hasCurrent ? " (now " + o.current + ")" : ""
    prefill({ source: "options browser", text: "Change " + o.path + from + " to " })
  }

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
    function searchOptions(query: string): void { root.view = "options"; root.optionsQuery = query; root.openPanel() }
    function askOption(n: int): string {
      if (n < 0 || n >= root.optionsResults.length) return "no result " + n
      root.askToChange(root.optionsResults[n]); return "ok"
    }
    function preview(action: string): string { return root.previewAnswer(action) }
    // The applied row's Undo (tests drive it here; the button runs the same).
    function undo(): string { root.undoLast(); return "ok" }
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
        items: root.transcript.count, attachments: root.attachments.length, chips: root.chips.map(function(c) { return c.label }),
        rows: root.rowSummary(),
        preview: root.preview ? { path: root.preview.path, state: root.preview.state, label: root.preview.label, reason: root.preview.reason } : null,
        options: { query: root.optionsQuery, busy: root.optionsBusy, total: root.optionsTotal,
          results: root.optionsResults.slice(0, 5).map(function(o) { return { path: o.path, current: o.current, hasCurrent: o.hasCurrent } }) } })
    }
  }
}
