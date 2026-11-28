#!/usr/bin/env node
// Per-test counts from `flutter test --file-reporter json:<file>`, as
// markdown for the CI job summary (and the job log): passed, failed,
// skipped, every skipped test by name (a green job doesn't mean a test ran),
// each test file's own counts, and any test file under the test folder that
// isn't in the report at all (it never ran). Reports only: the test step
// itself fails on a failure.
//   node tool/test_counts.mjs build/test-report.json [test]
import fs from 'node:fs';
import path from 'node:path';

const file = process.argv[2];
const testDir = process.argv[3] ?? 'test';
if (!file || !fs.existsSync(file)) {
  console.log(`No test report at ${file}.`);
  process.exit(0);
}
// Paths as the repo writes them: relative to where the tests ran, with /.
const rel = (p) => path.relative(process.cwd(), p).split(path.sep).join('/');
const suites = new Map();
const tests = new Map();
const perFile = new Map();
const countsFor = (p) => {
  if (!perFile.has(p)) perFile.set(p, { passed: 0, failed: 0, errors: 0, skipped: 0 });
  return perFile.get(p);
};
let passed = 0, failed = 0, errored = 0;
const skipped = [];
for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
  if (!line.trim()) continue;
  let e;
  try { e = JSON.parse(line); } catch { continue; }
  if (e.type === 'suite') {
    const p = e.suite.path ? rel(e.suite.path) : '?';
    suites.set(e.suite.id, p);
    countsFor(p);
  }
  if (e.type === 'testStart') tests.set(e.test.id, e.test);
  // Hidden: a file's loading, unless it fails.
  if (e.type === 'testDone' && !e.hidden) {
    const test = tests.get(e.testID);
    const p = suites.get(test?.suiteID) ?? '?';
    const counts = countsFor(p);
    if (e.skipped) {
      counts.skipped++;
      const reason = test?.metadata?.skipReason;
      skipped.push(`${p}: ${test?.name ?? '?'}` + (reason ? ` (${reason})` : ''));
    } else if (e.result === 'success') {
      passed++;
      counts.passed++;
    } else if (e.result === 'failure') {
      failed++;
      counts.failed++;
    } else {
      errored++;
      counts.errors++;
    }
  }
}
const byPath = (a, b) => (a < b ? -1 : a > b ? 1 : 0);
console.log(`### Tests: ${passed} passed, ${failed} failed, ${errored} errors, ${skipped.length} skipped`);
console.log(`(${suites.size} test files)`);
if (skipped.length) {
  console.log('\nSkipped:');
  for (const s of skipped) console.log(`- ${s}`);
}
const onDisk = fs.existsSync(testDir)
  ? fs.readdirSync(testDir, { recursive: true })
      .map((p) => path.join(testDir, p))
      .filter((p) => p.endsWith('_test.dart') && fs.statSync(p).isFile())
      .map(rel)
  : [];
const neverRan = onDisk.filter((p) => !perFile.has(p)).sort(byPath);
if (neverRan.length) {
  console.log('\nTest files not in the report (they never ran):');
  for (const p of neverRan) console.log(`- ${p}`);
}
console.log('\n<details><summary>Per test file</summary>\n');
console.log('| File | Passed | Failed | Errors | Skipped |');
console.log('|---|---:|---:|---:|---:|');
for (const p of [...perFile.keys()].sort(byPath)) {
  const c = perFile.get(p);
  console.log(`| ${p} | ${c.passed} | ${c.failed} | ${c.errors} | ${c.skipped} |`);
}
console.log('\n</details>');
