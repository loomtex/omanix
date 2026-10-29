// checks.card-goldens: render a fixture request directory with the plugin's
// own CardModel.js (the file the QML imports) and print the model and its
// text form. usage: node render.js <CardModel.js> <request-dir> <out-prefix>
const fs = require("fs");
const path = require("path");
const [cardModelJs, dir, out] = process.argv.slice(2);
const src = fs.readFileSync(cardModelJs, "utf8").replace(/^\.pragma .*$/m, "");
const mod = { exports: {} };
new Function("module", src)(mod);
const read = (f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")); } catch (e) { return null; } };
const t = read("test.json") || {};
const m = mod.exports.cardModel({ request: read("request.json"), review: read("review.json"), card: read("kind/card.json"),
  pendingIndex: t.pendingIndex || 0, pendingTotal: t.pendingTotal || 1, agent: t.agent, human: t.human });
fs.writeFileSync(out + ".json", JSON.stringify(m, null, 2) + "\n");
fs.writeFileSync(out + ".txt", mod.exports.cardText(m));
