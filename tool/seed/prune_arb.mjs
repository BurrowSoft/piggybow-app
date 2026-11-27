#!/usr/bin/env node
// Piggybow seed: drops the strings no code uses from lib/l10n/app_en.arb.
//   node tool/seed/prune_arb.mjs [repo]      (default: the current directory)
// A key stays when `.key` appears in a Dart file under lib/ (the generated
// l10n code aside) or test/ that imports the generated AppLocalizations (a
// getter of another class with the same name doesn't count). An entry is a
// key and its JSON value (a metadata object may span lines); anything else
// fails, so nothing is dropped by accident.
// Idempotent: on a pruned file it changes nothing.
import fs from 'node:fs';
import path from 'node:path';

const root = process.argv[2] ?? '.';
const arbPath = path.join(root, 'lib', 'l10n', 'app_en.arb');
const lines = fs.readFileSync(arbPath, 'utf8').split('\n');

function* dartFiles(dir) {
  if (!fs.existsSync(dir)) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (e.name !== 'gen') yield* dartFiles(p); }
    else if (e.name.endsWith('.dart')) yield p;
  }
}
const code = [...dartFiles(path.join(root, 'lib')), ...dartFiles(path.join(root, 'test'))]
  .map((f) => fs.readFileSync(f, 'utf8'))
  .filter((s) => s.includes('l10n/gen/app_localizations'))
  .join('\n');
const used = (key) => new RegExp(`\\.${key}\\b`).test(code);

const entry = /^  "(@?)([A-Za-z0-9_]+)": (.*)$/;
const parses = (v) => { try { JSON.parse(v.replace(/,\s*$/, '')); return true; } catch { return false; } };
const out = [];
let kept = 0, dropped = 0;
for (let i = 0; i < lines.length; i++) {
  const line = lines[i];
  if (line === '{' || line === '}' || line.trim() === '' || line.startsWith('  "@@')) { out.push(line); continue; }
  const m = entry.exec(line);
  if (!m) { console.error(`line ${i + 1}: not an entry`); process.exit(1); }
  const [, meta, key] = m;
  // An entry may span lines (a metadata object): gather until it parses.
  const block = [line];
  let value = m[3];
  while (!parses(value)) {
    i++;
    if (i >= lines.length) { console.error(`entry ${key}: never closes`); process.exit(1); }
    block.push(lines[i]);
    value += '\n' + lines[i];
  }
  if (used(key)) { out.push(...block); if (!meta) kept++; }
  else if (!meta) dropped++;
}
// Tidy: no comma after the last entry, no runs of blank lines.
let text = out.join('\n').replace(/\n{3,}/g, '\n\n').replace(/\{\n\n/, '{\n');
text = text.replace(/,(\s*)\n\}\s*$/, '$1\n}\n').replace(/\n\n\}\n$/, '\n}\n');
JSON.parse(text); // still a valid ARB
fs.writeFileSync(arbPath, text);
console.log(`app_en.arb: kept ${kept} strings, dropped ${dropped}`);
