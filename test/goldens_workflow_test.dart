import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/workflows.dart';

/// The golden baselines workflow (.github/workflows/goldens.yaml, decision
/// 44): manual, read-only, no secrets. It renders the golden-tagged tests on
/// the runner and Flutter that ci.yaml's tests compare them on, and uploads
/// only the PNGs and their manifest, for 3 days, after a guard.
void main() {
  final wf = File('.github/workflows/goldens.yaml').readAsStringSync();
  final ci = File('.github/workflows/ci.yaml').readAsStringSync();

  test('manual only; read-only; no secrets; one render at a time', () {
    expect(wf, contains('\non:\n  workflow_dispatch:\n'));
    for (final trigger in [
      'pull_request',
      'push:',
      'schedule:',
      'workflow_run',
      'workflow_call',
      'repository_dispatch',
    ]) {
      expect(wf, isNot(contains(trigger)), reason: trigger);
    }
    expect(wf, contains('\npermissions:\n  contents: read\n'));
    expect(wf, isNot(contains(': write')));
    expect(wf, isNot(contains('secrets.')));
    expect('uses: actions/checkout@'.allMatches(wf), hasLength(1));
    expect(wf, contains('persist-credentials: false'));
    // Job-level: a run joins the group only when its job runs.
    expect(
      wf,
      contains(
        '\n    concurrency:\n      group: goldens\n'
        '      cancel-in-progress: false\n',
      ),
    );
    expect(wf, isNot(contains('\nconcurrency:')));
  });

  test("rendered where they're compared: ci.yaml's runner and Flutter", () {
    final check = jobSection(ci, 'check');
    expect(check, contains('flutter test'));
    final runner = valuesOf(check, 'runs-on');
    final flutter = valuesOf(check, 'flutter-version');
    expect(runner, hasLength(1));
    expect(flutter, hasLength(1));
    expect(valuesOf(wf, 'runs-on'), runner);
    expect(valuesOf(wf, 'flutter-version'), flutter);
    expect(valuesOf(wf, 'channel'), valuesOf(check, 'channel'));
  });

  test('the ref reaches the shell only as env, and is checked', () {
    final blocks = runBlocks(wf);
    expect(blocks.length, greaterThanOrEqualTo(5), reason: 'run steps found');
    for (final block in blocks) {
      expect(block, isNot(contains(r'${{')), reason: block);
    }
    final inputs = RegExp(
      r'^.*\$\{\{ inputs\..*$',
      multiLine: true,
    ).allMatches(wf).map((m) => m.group(0)!.trim()).toList();
    expect(inputs, [r'REF: ${{ inputs.ref }}']);
    expect(
      wf,
      contains(r'[[ "$REF" =~ ^[A-Za-z0-9._/-]{1,100}$ && "$REF" != *..* ]]'),
    );
    expect(wf, contains(r'ref: ${{ steps.in.outputs.ref }}'));
  });

  test(
    'every golden-tagged test, every golden rewritten, then the manifest',
    () {
      final start = wf.indexOf(r'touch "$RUNNER_TEMP/goldens-start"');
      final render = wf.indexOf('flutter test --tags golden --update-goldens');
      final manifest = wf.indexOf('dart run tool/golden_manifest.dart write');
      expect(start, greaterThan(0));
      expect(render, greaterThan(start));
      expect(manifest, greaterThan(render));
      expect(
        wf,
        contains(r'--file-reporter json:"$RUNNER_TEMP/goldens-report.json"'),
      );
      final args = wf.substring(manifest, wf.indexOf('\n      - ', manifest));
      for (final arg in [
        r'--report "$RUNNER_TEMP/goldens-report.json"',
        r'--since "$RUNNER_TEMP/goldens-start"',
        r'--out "$OUT"',
        r'--sha "$SHA"',
        r'--ref "$REF"',
        r'--run-id "$GITHUB_RUN_ID"',
        r'--run-attempt "$GITHUB_RUN_ATTEMPT"',
        r'--flutter "$flutter_version"',
      ]) {
        expect(args, contains(arg), reason: arg);
      }
    },
  );

  test('only the PNGs and the manifest leave, for 3 days, after the guard', () {
    final guard = wf.indexOf('- name: Only PNGs and the manifest');
    final upload = wf.indexOf('uses: actions/upload-artifact@');
    expect(guard, greaterThan(wf.indexOf('tool/golden_manifest.dart write')));
    expect(upload, greaterThan(guard));
    expect('actions/upload-artifact'.allMatches(wf), hasLength(1));
    final check = wf.substring(guard, upload);
    expect(check, contains('-type d -o -type l'));
    expect(check, contains("! -name '*.png' ! -name 'manifest.json'"));
    expect(check, contains('89504e470d0a1a0a'));
    expect(r'OUT: ${{ runner.temp }}/goldens'.allMatches(wf), hasLength(2));
    final step = wf.substring(upload);
    expect(step, contains("steps.guard.outcome == 'success'"));
    expect(step, contains('path: \${{ runner.temp }}/goldens\n'));
    expect(step, contains('retention-days: 3\n'));
    expect(step, contains('if-no-files-found: error'));
  });

  test('the readers see what they pin', () {
    const sample = '''
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - name: x
        run: |
          echo "\${{ inputs.x }}"
      - run: echo ok
  b:
    runs-on: macos-latest
''';
    expect(runBlocks(sample), hasLength(2));
    expect(runBlocks(sample).first, contains(r'${{'));
    expect(runBlocks(sample).last, 'echo ok');
    expect(valuesOf(jobSection(sample, 'a'), 'runs-on'), ['ubuntu-latest']);
    expect(valuesOf(jobSection(sample, 'b'), 'runs-on'), ['macos-latest']);
    expect(() => jobSection(sample, 'c'), throwsStateError);
  });
}
