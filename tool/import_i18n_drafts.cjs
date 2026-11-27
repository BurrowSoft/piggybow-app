// Localization plan (2026-11-05): copies the UX drafts
// specs/i18n/<lang>/app_<lang>.arb into lib/l10n. Every language is a draft,
// not offered until a native read ({pending:<lang>_reviewed}; AppConfig's
// <LANG>_OFFERED). Run from the app root with the specs folder, again after
// each draft round:
//   node tool/import_i18n_drafts.cjs ../specs
// pt-BR ships as app_pt.arb ("pt"): the pickers and the Flutter fallback go
// by language code, so a Brazilian (or any Portuguese) phone gets it.
// The draft's own @metadata is dropped (the template carries it); a value
// that is rightly the English word gets `x-same-as-en` from sameAsEn below,
// so check_l10n still catches anything else left in English.
// Fails when a key is missing, extra or loses a placeholder.
const fs = require('fs');
const path = require('path');

const specs = process.argv[2] || '../specs';
const en = JSON.parse(fs.readFileSync('lib/l10n/app_en.arb', 'utf8'));
const keys = Object.keys(en).filter((k) => !k.startsWith('@'));

// Draft folder → app locale code.
const langs = { fr: 'fr', es: 'es', 'pt-BR': 'pt', de: 'de', it: 'it' };

// Values equal to English on purpose (loanwords, units, format-only).
const units = ['sleepHours', 'exerciseMinutes', 'exercise90'];
const sameAsEn = {
  fr: [...units, 'focusStress', 'stressTitle', 'chartStress', 'exportStress',
    'toneDirect', 'entryDateLabel', 'meVersion', 'shareStory', 'shareFormat',
    'lock1Min', 'lock5Min'],
  es: units,
  pt: [...units, 'tabInsights', 'insightsTitle', 'exportCheckins',
    'shareStory'],
  de: ['focusStress', 'stressTitle', 'chartStress', 'exportStress',
    'optional', 'momentBadge', 'exportCheckins', 'meVersion', 'shareStory',
    'shareFormat'],
  it: [...units, 'emailLabel', 'passwordLabel', 'focusStress', 'stressTitle',
    'chartStress', 'exportStress', 'exportAccount'],
};

// The Me row's "AI" label in the words each language uses (UX 2026-11-05),
// and the "Me → AI" path in the text that names it. Italian prose says
// "AI", so it keeps it.
const aiLabel = { fr: 'IA', es: 'IA', pt: 'IA', de: 'KI' };
sameAsEn.it.push('meAi');

// The delete-account word typed to confirm (UX 2026-11-05); the drafts'
// "Type DELETE" prompt names it as {word}.
const deleteWord = {
  fr: 'SUPPRIMER', es: 'ELIMINAR', pt: 'APAGAR', de: 'LÖSCHEN', it: 'ELIMINA',
};
const fixUp = (code, k, v) => {
  if (k === 'deleteTypeConfirm') return v.replace(/\bDELETE\b/, '{word}');
  return v;
};

let failed = false;
for (const [folder, code] of Object.entries(langs)) {
  const file = path.join(specs, 'i18n', folder, `app_${folder.replace('-', '_')}.arb`);
  const draft = JSON.parse(fs.readFileSync(file, 'utf8'));
  draft.deleteWord ??= deleteWord[code];
  for (const k of Object.keys(draft)) {
    if (!k.startsWith('@') && typeof draft[k] === 'string') {
      draft[k] = fixUp(code, k, draft[k]);
    }
  }
  const out = {
    '@@locale': code,
    '@@x-status': draft['@@x-status'] ||
      `${folder} draft (UX & PM, localization-plan.md). Not offered until ${folder.replace('-', '_')}_reviewed.`,
  };
  for (const k of Object.keys(draft)) {
    if (!k.startsWith('@') && !(k in en)) {
      console.error(`${folder}: "${k}" is not in app_en.arb`);
      failed = true;
    }
  }
  for (const k of keys) {
    const v = draft[k];
    if (typeof v !== 'string' || !v.trim()) {
      console.error(`${folder}: missing "${k}"`);
      failed = true;
      continue;
    }
    const placeholders = Object.keys((en[`@${k}`] || {}).placeholders || {});
    for (const p of placeholders) {
      if (!v.includes(`{${p}`)) {
        console.error(`${folder}: "${k}" lost {${p}}`);
        failed = true;
      }
    }
    const ai = aiLabel[code];
    out[k] = !ai ? v : k === 'meAi' ? ai : v.replace(/ → AI(?![\p{L}])/gu, ` → ${ai}`);
    if (sameAsEn[code].includes(k)) out[`@${k}`] = { 'x-same-as-en': true };
  }
  fs.writeFileSync(`lib/l10n/app_${code}.arb`, JSON.stringify(out, null, 2) + '\n');
}
if (failed) process.exit(1);
console.log(`wrote ${Object.values(langs).map((c) => `app_${c}.arb`).join(', ')}`);
