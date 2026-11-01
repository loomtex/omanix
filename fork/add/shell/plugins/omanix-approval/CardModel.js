.pragma library

// The approval card's content (DESIGN §h.4, §g.4), as plain data: what the
// QML draws and what checks.card-goldens compares. Pure functions of the
// request directory's files (request.json, review.json, kind/card.json);
// everything here is text the collector (root), nuketown or the reviewer
// wrote, and it is shown as plain text, never as markup.

var REC_WORD = { approve: "APPROVE", deny: "DENY", ask: "LOOK CLOSER" }
var REVIEWER_SAYS = { approve: "matches", deny: "recommends deny", ask: "look closer" }

function str(v) { return v === undefined || v === null ? "" : String(v) }

function truncate(s, n) {
  s = str(s)
  return s.length > n ? s.slice(0, Math.max(0, n - 1)) + "…" : s
}

// One argv element, control characters made visible (§h.4 "Show command").
function escapeArg(s) {
  return str(s).replace(/[\u0000-\u001f\u007f]/g, function(c) {
    var map = { "\n": "\\n", "\t": "\\t", "\r": "\\r", "\u001b": "\\e" }
    if (map[c]) return map[c]
    var h = c.charCodeAt(0).toString(16)
    return "\\x" + (h.length < 2 ? "0" + h : h)
  })
}

function upper(s) { return str(s).toUpperCase() }

// review.json → what the AI review section says. The review line is a risk
// badge, the recommendation and the headline, then the concerns; the
// summary and "Can't see" are details (ⓘ). A review from before reviewers
// wrote a headline leads with its summary instead.
function reviewView(review, forRoot) {
  var r = review || { status: "missing" }
  var fallback = forRoot ? "Read the command." : "Check the diff."
  if (r.status === "ok") {
    var headline = typeof r.headline === "string" ? r.headline.trim() : ""
    return {
      state: "ok",
      heading: "AI REVIEW · can be wrong",
      headline: truncate(headline || r.summary, headline ? 200 : 300),
      hasHeadline: headline !== "",
      badge: upper(r.risk),
      summary: truncate(r.summary, 2000),
      risk: str(r.risk),
      recommendation: str(r.recommendation),
      recWord: REC_WORD[r.recommendation] || upper(r.recommendation),
      notes: (r.notes || []).map(function(n) { return truncate(n, 500) }),
      notShown: (r.not_shown || []).map(function(n) { return truncate(n, 500) }),
      reason: ""
    }
  }
  if (r.status === "pending") {
    return { state: "pending", heading: "AI REVIEW · reviewing…", headline: "Reviewer is reading this request…", hasHeadline: false,
      badge: "", summary: "The reviewer is still reading this request; this card updates when it's done.",
      risk: "", recommendation: "", recWord: "", notes: [], notShown: [], reason: "" }
  }
  var reason = r.status === "disabled" ? "no reviewer configured"
    : r.status === "skipped" ? str(r.reason || "skipped")
    : r.status === "missing" ? "no review"
    : str(r.reason || r.status)
  return { state: "none", heading: "No AI review (" + truncate(reason, 300) + "). " + fallback, headline: "", hasHeadline: false,
    badge: "", summary: "", risk: "", recommendation: "", recWord: "", notes: [], notShown: [], reason: truncate(reason, 300) }
}

// ---- the risk badge's colours, from the theme (colors.toml) -------------

function hexRgb(c) {
  var m = /^#?([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(str(c).trim())
  if (!m) return null
  var n = parseInt(m[1], 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

// WCAG relative luminance and contrast ratio.
function luminance(c) {
  var rgb = hexRgb(c)
  if (!rgb) return 0
  var l = rgb.map(function(v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) })
  return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
}

function contrast(a, b) {
  var x = luminance(a), y = luminance(b)
  return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05)
}

function firstColor() {
  for (var i = 0; i < arguments.length; i++) if (hexRgb(arguments[i])) return "#" + str(arguments[i]).trim().replace(/^#/, "").slice(0, 6).toLowerCase()
  return "#707880"
}

// palette: colors.toml keys (red, yellow, green, color1..3, accent, muted,
// background, foreground) plus the shell's urgent. The badge is the
// theme's red/yellow/green for high/medium/low (the nearest tokens when a
// theme has none); its text is the theme's background or foreground when
// that reads at 4.5:1, else black or white, whichever reads best (always
// at least 4.5:1). The word on the badge carries the risk; colour helps.
function badgeStyle(risk, palette) {
  var p = palette || {}
  var bg = risk === "high" ? firstColor(p.urgent, p.red, p.color1, "#c62828")
    : risk === "medium" ? firstColor(p.yellow, p.color3, p.orange, p.accent, "#b7791f")
    : risk === "low" ? firstColor(p.green, p.color2, p.accent, "#3f7f4f")
    : firstColor(p.muted, p.color8, "#707880")
  var text = null
  ;[p.background, p.foreground].forEach(function(c) { if (!text && hexRgb(c) && contrast(c, bg) >= 4.5) text = firstColor(c) })
  if (!text) text = contrast("#000000", bg) >= contrast("#ffffff", bg) ? "#000000" : "#ffffff"
  return { background: bg, text: text, contrast: Math.round(contrast(text, bg) * 100) / 100 }
}

// colors.toml text → { key: "#rrggbb" } (only quoted hex values).
function parsePalette(toml) {
  var out = {}
  str(toml).split("\n").forEach(function(line) {
    var m = /^\s*([a-z0-9_]+)\s*=\s*"(#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?)"/.exec(line)
    if (m) out[m[1]] = m[2]
  })
  return out
}

// "Can't see: …" in one line, ending with one full stop.
function cantSee(list) {
  var t = list.length ? list.join("; ") : "nothing"
  return /[.!?]$/.test(t) ? t : t + "."
}

function pkgsShort(packages) {
  var m = /^\s*([+-]?\d+)/.exec(str(packages))
  return m ? m[1] + " pkgs" : ""
}

// The change card (kind loom-switch): routine or full (§g.4 "Form").
function changeModel(input) {
  var req = input.request || {}
  var card = input.card || {}
  var rv = reviewView(input.review, false)
  var agent = str(input.agent || req.requester || "the agent")
  var flags = card.flags || []
  var kind = str(card.kind || "change")
  var request = str(card.request)
  var human = str(input.human)
  var byHuman = (req.origin === "root" && human !== "" && req.requester === human) || /^Your own commit/.test(request)

  var routine = kind === "undo" || kind === "update"
    || (rv.state === "ok" && rv.recommendation === "approve" && rv.risk === "low" && rv.notes.length === 0
        && flags.length === 0 && request !== "" && card.full !== true)

  var requestHeading, requestText
  if (kind === "update") { requestHeading = "SCHEDULED UPDATE"; requestText = str(card.title) }
  else if (kind === "undo") { requestHeading = "UNDO"; requestText = str(card.title) }
  else if (request === "") { requestHeading = "NO REQUEST GIVEN"; requestText = "Nobody said what this change is for. Read the diff." }
  else if (byHuman) { requestHeading = "YOUR OWN COMMIT"; requestText = request.replace(/^Your own commit:\s*/, "") }
  else { requestHeading = "YOUR REQUEST (as " + agent + " relayed it)"; requestText = request }

  var reviewer = rv.state === "ok" ? (REVIEWER_SAYS[rv.recommendation] || rv.recommendation)
    : rv.state === "pending" ? "reviewing…" : "no review (" + truncate(rv.reason, 60) + ")"

  var changes = []
  changes.push({ label: "Packages", text: str(card.packages) || "no package changes" })
  var files = card.files || []
  changes.push({ label: "Files", text: files.length ? truncate(files.join(", "), 400) : "none" })
  if (flags.length) changes.push({ label: "Flags", text: str(card.flagLine || flags.join("; ")), warn: true })
  changes.push({ label: "Build", text: str(card.out) ? "ok" : "not built" })
  if (card.lastRejection) changes.push({ label: "Last time", text: "you rejected a change: " + truncate(card.lastRejection.reason || card.lastRejection, 200) })
  if (card.notLoomSwitched) changes.push({ label: "Note", text: "the running system was not switched by loom (a manual switch since the last card)", warn: true })

  return {
    id: str(req.id),
    kind: "change",
    form: routine ? "routine" : "full",
    title: "Approve a change to this computer",
    pendingText: input.pendingTotal > 1 ? (input.pendingIndex + 1) + " of " + input.pendingTotal + " pending" : "",
    banner: {
      icon: "⛉",
      quote: kind === "update" || kind === "undo" ? truncate(card.title, 80) : "“" + truncate(request || card.title, 60) + "”",
      packages: kind === "update" ? "" : pkgsShort(card.packages),
      reviewer: "Reviewer: " + reviewer
    },
    requestHeading: requestHeading,
    requestText: truncate(requestText, 600),
    changes: changes,
    review: rv,
    buttons: [{ id: "diff", label: "Show git diff" }, { id: "nvd", label: "nvd diff" }],
    approveLabel: rv.recommendation === "deny" ? "Approve anyway" : "Approve",
    denyLabel: "Deny",
    detailsOpen: false
  }
}

// Every other request: the root-command card (one form).
function rootModel(input) {
  var req = input.request || {}
  var rv = reviewView(input.review, true)
  var runAs = req.run_as && req.run_as.user ? str(req.run_as.user) : "root"
  var who = str(req.requester || "the agent")
  var argv = (req.argv || []).map(escapeArg)
  var snaps = (req.snapshots || []).map(function(s) {
    return { path: str(s.path), snapshot: str(s.snapshot), sha256: str(s.sha256), executed: s.executed === true,
      label: str(s.path) + (s.executed === true ? "  (runs; the snapshot is what runs)" : "  (for review)") }
  })
  return {
    id: str(req.id),
    kind: "root",
    form: "root",
    title: who + " wants to run a command as " + runAs,
    pendingText: input.pendingTotal > 1 ? (input.pendingIndex + 1) + " of " + input.pendingTotal + " pending" : "",
    requestHeading: req.origin === "root" ? "STATED REASON" : upper(who) + "'S STATED REASON",
    requestText: str(req.why) ? "“" + truncate(req.why, 400) + "”" : "(no reason given)",
    command: { display: truncate(req.display || argv.join(" "), 800), argv: argv, runAs: runAs, snapshots: snaps,
      decrypt: (req.decrypt || []).map(str), notSnapshotted: rv.notShown },
    review: rv,
    // The command and script are details (ⓘ), with the review's summary.
    buttons: [],
    approveLabel: rv.risk === "high" || rv.recommendation === "deny" ? "Approve anyway" : "Approve",
    denyLabel: "Deny",
    // No review: the command is the only thing to read, so it starts open.
    detailsOpen: rv.state === "none"
  }
}

function cardModel(input) {
  var req = input.request || {}
  if (req.kind && req.kind.name === "loom-switch" && input.card) return changeModel(input)
  return rootModel(input)
}

// ---- text form: checks.card-goldens, and a readable dump for tests -------

function wrap(text, width) {
  var out = []
  str(text).split("\n").forEach(function(para) {
    var indent = /^ */.exec(para)[0]
    var line = ""
    para.slice(indent.length).split(" ").forEach(function(w) {
      if (line === "") line = w
      else if ((indent + line + " " + w).length <= width) line += " " + w
      else { out.push(indent + line); line = w }
    })
    out.push(indent + line)
  })
  return out
}

function pad(s, n) { s = str(s); while (s.length < n) s += " "; return s }

function cardText(m) {
  var W = 86
  if (m.form === "routine") {
    return " " + m.banner.icon + "  " + m.banner.quote + (m.banner.packages ? "  ·  " + m.banner.packages : "")
      + "  ·  " + m.banner.reviewer + "   [Details]  [" + m.approveLabel + "]  [✕]\n"
  }
  var lines = []
  function rule(title, right) {
    var head = "┌─ " + title + " "
    var tail = right ? " " + right + " ─┐" : "─┐"
    var fill = W + 4 - head.length - tail.length
    lines.push(head + new Array(Math.max(1, fill) + 1).join("─") + tail)
  }
  function sep(title) {
    var head = title ? "├─ " + title + " " : "├"
    lines.push(head + new Array(Math.max(1, W + 3 - head.length) + 1).join("─") + "┤")
  }
  function row(text) { wrap(text, W).forEach(function(l) { lines.push("│ " + pad(l, W) + " │") }) }

  rule(m.title, m.pendingText)
  if (m.kind === "root") row("  " + m.command.display)
  row(m.requestHeading)
  row("  " + m.requestText)
  if (m.kind === "change") {
    sep("WHAT CHANGES")
    m.changes.forEach(function(c) { row(pad(c.label, 10) + " " + c.text + (c.warn ? "  [!]" : "")) })
  }
  var rv = m.review
  if (rv.state === "none") {
    sep("")
    row(rv.heading)
  } else {
    sep(rv.heading)
    row(rv.state === "ok" ? "[" + rv.badge + "] " + rv.recWord + " · " + rv.headline : "… " + rv.headline)
    rv.notes.forEach(function(n) { row("  • " + n) })
  }
  row(pad("", W - 3) + "(i)")
  if (m.detailsOpen) {
    if (rv.state !== "none") {
      sep("DETAILS")
      row(rv.summary)
      if (rv.state === "ok") row("Can't see: " + cantSee(rv.notShown))
    }
    if (m.kind === "root") {
      sep("COMMAND (as " + m.command.runAs + ")")
      m.command.argv.forEach(function(a, i) { row("  argv[" + i + "] " + a) })
      m.command.snapshots.forEach(function(s) { row("  " + s.label + "  sha256 " + s.sha256.slice(0, 16) + "…") })
    }
  }
  sep("")
  row((m.buttons.length ? pad(m.buttons.map(function(b) { return "[" + b.label + "]" }).join("  "), 40) : pad("", 40))
    + "[" + m.denyLabel + "]   [" + m.approveLabel + "]")
  lines.push("└" + new Array(W + 3).join("─") + "┘")
  return lines.join("\n") + "\n"
}

// For node (checks.card-goldens); QML ignores this.
if (typeof module !== "undefined") module.exports = { cardModel: cardModel, cardText: cardText, reviewView: reviewView, escapeArg: escapeArg, cantSee: cantSee,
  badgeStyle: badgeStyle, parsePalette: parsePalette, contrast: contrast }
