#!/usr/bin/env node
// Piggybow seed: the mechanical part.
//
// Input: an empty directory X holding
//   git -c core.autocrlf=false archive ae241dd16af87511560d4791ba49d7a75a37e47b
// of BurrowSoft/moodbow-app (extract it with tar). Then:
//   SEED_OWNER_NAME=<the owner's first name> node tool/seed/seed.mjs X
// The seed commit is X after this script plus hand edits, so
// `diff -r X <seed commit>` shows exactly the hand edits.
//
// Steps (deterministic; sorted walk; prints names and counts only, never a value):
//   1. Delete the Moodbow features, native extras, server code and tooling
//      Piggybow doesn't carry (REMOVE below), and the tests of what's gone
//      (tests_removed.txt, beside this file).
//   2. Blank the backend values in env/*.json (v0.1 is on-device only) and
//      replace any Supabase project ref taken from them, everywhere.
//   3. Rename Moodbow -> Piggybow in file contents and paths, case-preserving
//      (moodbow, Moodbow, MOODBOW).
//   4. Neutralize the owner's name in attributions ("the owner").
//   5. Fail if a collected value is still present.
import fs from 'node:fs';
import path from 'node:path';

const root = process.argv[2];
if (!root || !fs.existsSync(path.join(root, 'pubspec.yaml'))) {
  console.error('usage: SEED_OWNER_NAME=<name> node seed.mjs <dir with the extracted archive>');
  process.exit(2);
}
// The owner's first name (step 4) comes from the environment: it's kept out
// of this repo entirely. Checked before anything is touched.
const NAME = process.env.SEED_OWNER_NAME ?? '';
if (!/^[A-Za-z]+$/.test(NAME)) {
  console.error('set SEED_OWNER_NAME to the owner\'s first name (one word; ask the team)');
  process.exit(2);
}
const rel = (p) => path.relative(root, p).split(path.sep).join('/');

// ---------------------------------------------------------------- 1. delete
// A path ending in "/" is a directory prefix; anything else is exact.
const REMOVE = `
.maestro/
docs/
README.md
TESTING.md
integration_test/
test_driver/
env/demo.json
.github/actions/maestro-emulator/
.github/workflows/demo-apk.yaml
.github/workflows/device-rows.yaml
.github/workflows/maestro-full.yaml
.github/workflows/reminder-now-apk.yaml
.github/workflows/staging-release-apk.yaml
.github/workflows/video-takes.yaml
assets/app_icons/
assets/brand/
supabase/functions/
supabase/migrations/
supabase/tests/
supabase/config.toml
supabase/.gitignore
tool/bo/
tool/demo/
tool/device-rows/
tool/video-seed/
tool/video-takes/
tool/walk-rel132/
tool/walk-rel140/
tool/check_countries.dart
tool/db_pretest.sh
tool/gen_app_icons_test.dart
tool/gen_country_names.js
tool/gen_export_csv_routine.mjs
tool/gen_mood_prompts_contract.mjs
tool/gen_patterns_v2.mjs
tool/gen_prompts.cjs
tool/gen_prompts_library.cjs
tool/gen_showed_up_contract.mjs
tool/gen_th_arb.cjs
tool/widget_faces.cjs
lib/demo/
lib/main_demo.dart
lib/wear_main.dart
lib/features/age/
lib/features/appointment/
lib/features/bo/
lib/features/entry/
lib/features/insights/
lib/features/letters/
lib/features/reflect/
lib/features/review/
lib/features/routine/
lib/features/safety/
lib/features/safety_plan/
lib/features/share/
lib/features/timeline/
lib/features/today/
lib/features/toolbox/
lib/features/wear/
lib/features/year/
lib/features/start/first_open_screen.dart
lib/features/shell/bo_space.dart
lib/features/plus/christmas.dart
lib/features/plus/christmas_cards.dart
lib/features/plus/journal_pdf.dart
lib/features/plus/journal_pdf_rules.dart
lib/features/plus/journal_pdf_screen.dart
lib/features/plus/me_app_icon.dart
lib/features/plus/me_palettes.dart
lib/features/plus/plus_insights.dart
lib/features/plus/today_plus_card.dart
lib/features/plus/what_lifts_me_card.dart
lib/features/plus/year_review.dart
lib/features/plus/year_review_screen.dart
lib/features/me/ai_consent_sheet.dart
lib/features/me/backup_screen.dart
lib/features/me/export_cleanup.dart
lib/features/me/export_share.dart
lib/features/me/import_controller.dart
lib/features/me/import_picker.dart
lib/features/me/import_screen.dart
lib/features/me/me_ai_section.dart
lib/features/me/me_bo_section.dart
lib/features/me/me_picture.dart
lib/features/me/me_region_section.dart
lib/features/me/past_reports_screen.dart
lib/core/age_signal.dart
lib/core/age_signal_store.dart
lib/core/app_icon.dart
lib/core/country_names.dart
lib/core/device_only_text.dart
lib/core/health_fill.dart
lib/core/health_source.dart
lib/core/help_taps.dart
lib/core/home_widget.dart
lib/core/ime_fallback.dart
lib/core/png.dart
lib/core/search_fold.dart
lib/core/sounds.dart
lib/data/bo.dart
lib/data/bo_picture.dart
lib/data/export_csv.dart
lib/data/export_text.dart
lib/data/import/
lib/data/journal.dart
lib/data/letters.dart
lib/data/pictures.dart
lib/data/routine.dart
lib/data/safety_plan.dart
lib/data/tags.dart
lib/data/toolbox.dart
lib/data/trusted_share.dart
lib/theme/mood_face.dart
lib/theme/sunrise_steps.dart
lib/core/user_store.dart
lib/data/supabase_backend.dart
lib/data/backend.dart
lib/data/refresh_safe_client.dart
lib/features/me/me_screen.dart
lib/features/me/delete_account_dialog.dart
lib/features/onboarding/
lib/features/plus/plus_screen.dart
lib/features/plus/me_plus_section.dart
lib/features/plus/plus_widgets.dart
lib/l10n/app_de.arb
lib/l10n/app_es.arb
lib/l10n/app_fr.arb
lib/l10n/app_it.arb
lib/l10n/app_pt.arb
lib/l10n/app_th.arb
lib/features/reminder/reminder_taps.dart
android/wear/
android/app/src/dev/
android/app/src/staging/
android/app/src/health/
android/app/src/nohealth/
android/app/src/main/kotlin/com/burrowsoft/moodbow/AppIcons.kt
android/app/src/main/kotlin/com/burrowsoft/moodbow/ImeRetry.kt
android/app/src/main/kotlin/com/burrowsoft/moodbow/MoodbowWidget.kt
android/app/src/main/kotlin/com/burrowsoft/moodbow/SleepPieces.kt
android/app/src/main/kotlin/com/burrowsoft/moodbow/VoiceChannel.kt
android/app/src/main/kotlin/com/burrowsoft/moodbow/sounds/
android/app/src/main/kotlin/com/burrowsoft/moodbow/wear/
android/app/src/test/
android/app/debug-shared.keystore
android/app/src/main/res/layout/
android/app/src/main/res/xml/moodbow_widget_info.xml
android/app/src/main/res/values/help_strings.xml
android/app/src/main/res/values/widget.xml
android/app/src/main/res/values-night/widget.xml
android/app/src/main/res/values-de/
android/app/src/main/res/values-es/
android/app/src/main/res/values-fr/
android/app/src/main/res/values-it/
android/app/src/main/res/values-pt/
android/app/src/main/res/values-th/
android/app/src/main/res/drawable-night/
android/app/src/main/res/drawable/widget_background.xml
android/app/src/main/res/drawable/widget_face_1.xml
android/app/src/main/res/drawable/widget_face_2.xml
android/app/src/main/res/drawable/widget_face_3.xml
android/app/src/main/res/drawable/widget_face_4.xml
android/app/src/main/res/drawable/widget_face_5.xml
ios/Flutter/Debug-demo.xcconfig
ios/Flutter/Profile-demo.xcconfig
ios/Flutter/Release-demo.xcconfig
ios/Runner.xcodeproj/xcshareddata/xcschemes/demo.xcscheme
ios/Runner/de.lproj/
ios/Runner/es.lproj/
ios/Runner/fr.lproj/
ios/Runner/it.lproj/
ios/Runner/pt-BR.lproj/
ios/Runner/th.lproj/
ios/Runner/Assets.xcassets/AppIcon-calm_sea.appiconset/
ios/Runner/Assets.xcassets/AppIcon-five_moods.appiconset/
ios/Runner/Assets.xcassets/AppIcon-night.appiconset/
ios/Runner/Assets.xcassets/AppIcon-simple.appiconset/
ios/Runner/Assets.xcassets/AppIcon-sunrise.appiconset/
`.trim().split('\n');

// Supabase contracts: only these stay (the Plus plumbing and the error codes).
const KEEP_CONTRACTS = new Set(['plus-entitlement.json', 'errors.md']);
// Launcher icons: only the default set stays (the Plus app-icon picker is out).
const ALT_ICON = /(^|\/)(ic_launcher|AppIcon)[-_](night|sunrise|five_moods|calm_sea|simple)(_|\.|\/|$)/;

function* walk(d) {
  const es = fs.readdirSync(d, { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1));
  for (const e of es) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) yield* walk(p);
    else yield p;
  }
}
const removed = (r) =>
  REMOVE.some((x) => (x.endsWith('/') ? r.startsWith(x) : r === x)) ||
  (r.startsWith('supabase/contracts/') && !KEEP_CONTRACTS.has(r.slice('supabase/contracts/'.length))) ||
  (r.startsWith('android/app/src/main/res/') && ALT_ICON.test(r));

let nDel = 0;
for (const p of [...walk(root)]) {
  if (removed(rel(p))) { fs.unlinkSync(p); nDel++; }
}
// Tests that only exercise what was deleted (by subject); see TESTS_REMOVED.
const TESTS_REMOVED = fs.existsSync(new URL('./tests_removed.txt', import.meta.url))
  ? fs.readFileSync(new URL('./tests_removed.txt', import.meta.url), 'utf8').split(/\r?\n/).map((l) => l.replace(/#.*/, '').trim()).filter(Boolean)
  : [];
for (const t of TESTS_REMOVED) {
  const p = path.join(root, t);
  if (fs.existsSync(p)) { fs.unlinkSync(p); nDel++; }
}
// Empty directories left behind.
function prune(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) if (e.isDirectory()) prune(path.join(d, e.name));
  if (d !== root && fs.readdirSync(d).length === 0) fs.rmdirSync(d);
}
prune(root);
console.log(`1. deleted ${nDel} files`);

// ------------------------------------------------------------ 2. scrub env
const KEYS = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SENTRY_DSN', 'REGION_HOST'];
const envDir = path.join(root, 'env');
const values = new Set();
const refs = new Set();
for (const f of fs.readdirSync(envDir).filter((x) => x.endsWith('.json')).sort()) {
  const p = path.join(envDir, f);
  let s = fs.readFileSync(p, 'utf8');
  const o = JSON.parse(s);
  for (const k of KEYS) {
    const v = o[k];
    if (typeof v !== 'string' || v === '') continue;
    values.add(v);
    const m = /^https:\/\/([a-z]{20})\.supabase\.co/.exec(v);
    if (m) refs.add(m[1]);
    s = s.replace(new RegExp(`("${k}"\\s*:\\s*)"[^"]*"`), '$1""');
  }
  fs.writeFileSync(p, s);
}
if (values.size === 0 || refs.size === 0) { console.error('2. nothing collected from env: fail closed'); process.exit(1); }
console.log(`2. blanked ${values.size} env values; ${refs.size} project refs collected`);

// ------------------------------------------------- 3 + 4. contents and paths
const BINARY = /\.(png|jpe?g|gif|webp|ico|ttf|otf|jar|keystore|jks|zip|gz|pdf)$/i;
const PLACEHOLDER_REF = 'examplerefexampleref';
const renameText = (s) => s.replace(/moodbow/g, 'piggybow').replace(/Moodbow/g, 'Piggybow').replace(/MOODBOW/g, 'PIGGYBOW');
// The owner's first name ("<name>'s" / "<name>") -> "the owner's" / "the
// owner"; "The" at a line or comment start, or after the end of a sentence.
// Their to-do file's name -> "the owner's to-do list" (NAME, checked above).
const owner = (s) =>
  s
    .replace(new RegExp(`\\b${NAME.toUpperCase()}\\.md\\b`, 'g'), "the owner's to-do list")
    .replace(new RegExp(`(^[ \\t]*(?:\\/\\/\\/?|#|\\*|<!--)?[ \\t]*|[.!?][ \\t]+)?\\b${NAME}('s)?\\b`, 'gm'), (all, pre, poss) =>
      (pre ?? '') + (pre !== undefined ? 'The owner' : 'the owner') + (poss ?? ''));
let nText = 0;
let nOwner = 0;
const leftovers = [];
for (const p of [...walk(root)]) {
  if (BINARY.test(p)) continue;
  const buf = fs.readFileSync(p);
  if (buf.includes(0)) continue;
  const s = buf.toString('utf8');
  let t = s;
  for (const r of refs) t = t.split(r).join(PLACEHOLDER_REF);
  t = renameText(t);
  const o = owner(t);
  if (o !== t) nOwner++;
  t = o;
  if (t !== s) { fs.writeFileSync(p, t); nText++; }
  for (const v of values) if (t.includes(v)) leftovers.push(rel(p));
}
// Paths: deepest first, so a directory moves after its files.
const all = [];
(function collect(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) collect(p);
    all.push(p);
  }
})(root);
all.sort((a, b) => b.length - a.length || (a < b ? -1 : 1));
let nPath = 0;
for (const p of all) {
  const base = path.basename(p);
  const nb = renameText(base);
  if (nb !== base) {
    const np = path.join(path.dirname(p), nb);
    if (fs.existsSync(np)) { console.error(`3. rename target exists: ${rel(np)}`); process.exit(1); }
    fs.renameSync(p, np);
    nPath++;
  }
}
console.log(`3. renamed in ${nText} files and ${nPath} paths; 4. owner neutralized in ${nOwner} files`);

// ------------------------------------------------------------- 5. leftovers
if (leftovers.length) { console.error(`5. LEFTOVER values in: ${[...new Set(leftovers)].join(', ')}`); process.exit(1); }
console.log('5. ok: no collected value remains');
