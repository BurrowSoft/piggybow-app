#!/usr/bin/env node
// Per-test counts from `flutter test --file-reporter json:<file>`, as
// markdown for the CI job summary: passed, failed, skipped, and every
// skipped test by name (a green job doesn't mean a test ran). Reports only:
// the test step itself fails on a failure.
//   node tool/test_counts.mjs build/test-report.json
import fs from 'node:fs';

const file = process.argv[2];
if (!file || !fs.existsSync(file)) {
  console.log(`No test report at ${file}.`);
  process.exit(0);
}
const names = new Map();
const suites = new Map();
const testSuite = new Map();
let passed = 0, failed = 0, errored = 0;
const skipped = [];
for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
  if (!line.trim()) continue;
  let e;
  try { e = JSON.parse(line); } catch { continue; }
  if (e.type === 'suite') suites.set(e.suite.id, e.suite.path);
  if (e.type === 'testStart') {
    names.set(e.test.id, e.test.name);
    testSuite.set(e.test.id, e.test.suiteID);
    if (e.test.metadata?.skip) {
      skipped.push(`${suites.get(e.test.suiteID) ?? '?'}: ${e.test.name}` +
        (e.test.metadata.skipReason ? ` (${e.test.metadata.skipReason})` : ''));
    }
  }
  if (e.type === 'testDone' && !e.hidden && !e.skipped) {
    if (e.result === 'success') passed++;
    else if (e.result === 'failure') failed++;
    else errored++;
  }
}
console.log(`### Tests: ${passed} passed, ${failed} failed, ${errored} errors, ${skipped.length} skipped`);
console.log(`(${suites.size} test files)`);
if (skipped.length) {
  console.log('\nSkipped:');
  for (const s of skipped) console.log(`- ${s}`);
}
