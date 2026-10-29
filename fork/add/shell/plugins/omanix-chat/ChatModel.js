.pragma library

// omanix.chat's pure helpers (DESIGN §h.3, §h.6): the safe Markdown subset,
// the suggestion chips and intent templates. No I/O.

function esc(s) {
  return String(s === undefined || s === null ? "" : s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

function domainOf(url) {
  var m = /^[a-z][a-z0-9+.-]*:\/\/([^\/?#:]+)/i.exec(String(url || ""))
  return m ? m[1].toLowerCase() : ""
}

function inline(s) {
  // Everything is escaped first; only the tags added here exist afterwards.
  var t = esc(s)
  t = t.replace(/`([^`]+)`/g, function(m, c) { return "<font face=\"monospace\">" + c + "</font>" })
  t = t.replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
  t = t.replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>")
  // Links never become links: "text (domain)".
  t = t.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function(m, text, url) {
    var d = domainOf(url.replace(/&amp;/g, "&"))
    return text + (d ? " (" + d + ")" : "")
  })
  return t
}

// Markdown subset → Qt StyledText: paragraphs, lists, inline code, code
// blocks, bold/italic, links as "text (domain)". No images, no HTML.
function markdown(src) {
  var lines = String(src || "").split("\n")
  var out = []
  var inCode = false
  var code = []
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i]
    if (/^```/.test(l)) {
      if (inCode) { out.push("<pre>" + esc(code.join("\n")) + "</pre>"); code = []; inCode = false }
      else inCode = true
      continue
    }
    if (inCode) { code.push(l); continue }
    var li = /^\s*(?:[-*]|\d+\.)\s+(.*)$/.exec(l)
    if (li) { out.push("&nbsp;&nbsp;• " + inline(li[1])); continue }
    var h = /^#{1,6}\s+(.*)$/.exec(l)
    if (h) { out.push("<b>" + inline(h[1]) + "</b>"); continue }
    out.push(inline(l))
  }
  if (inCode) out.push("<pre>" + esc(code.join("\n")) + "</pre>")
  return out.join("<br>")
}

function renderIntent(template, fields) {
  return String(template || "").replace(/\{(label|value|selection)\}/g, function(m, k) {
    return fields && fields[k] !== undefined ? String(fields[k]) : ""
  })
}

// data/chips/rules.json against local facts (computed in the human session
// by omanix-chat-facts; never by the agent). At most four chips.
function chips(rules, facts, agent) {
  var out = []
  var f = facts || {}
  ;(rules && rules.rules ? rules.rules : []).forEach(function(r) {
    if (out.length >= 4) return
    var items = []
    if (r.when === "overlay") items = (f.overlays || []).map(function(a) { return { area: a } })
    else if (r.when === "failedUnit") items = (f.failedUnits || []).map(function(u) { return { unit: u } })
    else if (r.when === "updatePending") items = f.updatePending ? [{}] : []
    else if (r.when === "rolledBack") items = f.rolledBackRecently ? [{}] : []
    else if (r.when === "newDevice") items = (f.newDevices || []).map(function(d) { return { device: d } })
    else if (r.when === "firstDays") items = (f.daysSinceFirstLogin !== undefined && f.daysSinceFirstLogin < (r.days || 7)) ? [{}] : []
    items.forEach(function(v) {
      if (out.length >= 4) return
      var fill = function(s) { return String(s || "").replace(/\{(area|unit|device|agent)\}/g, function(m, k) { return k === "agent" ? agent : (v[k] || "") }) }
      out.push({ id: r.id, label: fill(r.chip), text: fill(r.text || r.chip) })
    })
  })
  return out
}

// One bridge event (loom.chat/v1) → how the transcript changes.
function activityLabel(e) {
  var label = String(e.label || e.kind || "")
  return label + (e.detail ? " — " + e.detail : "") + (e.external ? "  ⚠ external content" : "")
}

function progressLabel(e) {
  var phases = { eval: "evaluating", build: "building", review: "review" }
  var p = phases[e.phase] || String(e.phase || "")
  return "Checking · " + p + (e.total ? " " + (e.done || 0) + "/" + e.total : "")
}

if (typeof module !== "undefined") module.exports = { markdown: markdown, chips: chips, renderIntent: renderIntent, domainOf: domainOf }
