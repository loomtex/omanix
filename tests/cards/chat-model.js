// checks.chat-model: the chat's Markdown subset stays safe (§h.1 rule 7,
// §h.3.3) and the chips follow data/chips/rules.json. Pure; runs ChatModel.js
// as the panel does. usage: node chat-model.js <ChatModel.js> <rules.json>
const fs = require("fs");
const assert = require("assert");
const [js, rulesPath] = process.argv.slice(2);
const mod = { exports: {} };
new Function("module", fs.readFileSync(js, "utf8").replace(/^\.pragma .*$/m, ""))(mod);
const { markdown, chips, renderIntent, domainOf } = mod.exports;

// Everything the agent writes is escaped before the subset's own tags.
const evil = markdown('<img src="file:///etc/passwd"> <a href="x">y</a> <b onmouseover=1>z</b>');
assert(!/<img|<a |<b /.test(evil), evil);
assert(evil.includes("&lt;img"), evil);
// Links are text plus their domain, never anchors.
assert.strictEqual(markdown("see [the docs](https://nixos.org/manual/x?a=1&b=2)"), "see the docs (nixos.org)");
assert.strictEqual(markdown("[x](javascript:alert(1))"), "x)");
assert(!/<a/.test(markdown("[x](javascript:alert(1))")));
// The subset: bold, italic, inline code, lists, code blocks.
assert.strictEqual(markdown("**b** and *i*"), "<b>b</b> and <i>i</i>");
assert(markdown("`nix build`").includes('<font face="monospace">nix build</font>'));
assert(markdown("- one\n- two").includes("• one<br>&nbsp;&nbsp;• two"));
assert(markdown("```\n<script>\n```").includes("<pre>&lt;script&gt;</pre>"));
assert.strictEqual(domainOf("https://Claude.AI/oauth?x"), "claude.ai");

// Templates: only {label} {value} {selection}.
assert.strictEqual(renderIntent("Make {label} my default {kind}.", { label: "Firefox" }), "Make Firefox my default {kind}.");
assert.strictEqual(renderIntent("Set the unlock screen to {selection}", {}), "Set the unlock screen to ");

// Chips: at most four, from local facts.
const rules = JSON.parse(fs.readFileSync(rulesPath, "utf8"));
const c = chips(rules, { failedUnits: ["foo.service", "bar.service"], overlays: ["monitors"], updatePending: true,
  rolledBackRecently: true, daysSinceFirstLogin: 2 }, "ada");
assert.strictEqual(c.length, 4, JSON.stringify(c));
assert.deepStrictEqual(c.map((x) => x.label), ["What went wrong with my last change?", "Why did foo.service fail?",
  "Why did bar.service fail?", "What's in this update?"]);
const quiet = chips(rules, { daysSinceFirstLogin: 30 }, "ada");
assert.strictEqual(quiet.length, 0);
const fresh = chips(rules, { daysSinceFirstLogin: 0, overlays: ["font"] }, "ada");
assert.deepStrictEqual(fresh.map((x) => x.label), ["Make font stick", "What can I change?", "Show me around", "Install an app"]);
console.log("chat-model: ok");
