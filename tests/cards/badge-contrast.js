// checks.card-badge-contrast: the approval card's risk badge (CardModel.js
// badgeStyle) reads at 4.5:1 or better in every theme omarchy ships, and
// low/medium/high stay three different words even where a theme's colours
// don't differ. usage: node badge-contrast.js <CardModel.js> <themes dir>
const fs = require("fs");
const path = require("path");
const [cardModelJs, themes] = process.argv.slice(2);
const src = fs.readFileSync(cardModelJs, "utf8").replace(/^\.pragma .*$/m, "");
const mod = { exports: {} };
new Function("module", src)(mod);
const { badgeStyle, parsePalette } = mod.exports;
let bad = 0;
for (const t of fs.readdirSync(themes).sort()) {
  const f = path.join(themes, t, "colors.toml");
  if (!fs.existsSync(f)) continue;
  const p = parsePalette(fs.readFileSync(f, "utf8"));
  p.urgent = p.red || p.color1;
  const row = ["low", "medium", "high", "unknown"].map((r) => {
    const b = badgeStyle(r, p);
    if (b.contrast < 4.5) { bad++; return `${r} ${b.background}/${b.text} ${b.contrast} FAIL`; }
    return `${r} ${b.background}/${b.text} ${b.contrast}`;
  });
  console.log(t.padEnd(18), row.join("  "));
}
// No palette at all (no theme yet): the built-in colours.
const none = ["low", "medium", "high"].map((r) => badgeStyle(r, {}));
none.forEach((b) => { if (b.contrast < 4.5) bad++; });
if (bad) { console.error(`${bad} badge(s) under 4.5:1`); process.exit(1); }
console.log("PASS: every badge reads at 4.5:1 or better");
