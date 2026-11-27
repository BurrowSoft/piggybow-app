import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The CI emulator job (.github/workflows/emulator.yaml and
/// tool/emulator/run.sh): manual or by label, read-only, no secrets. The APK
/// it tests is built in the same job from the commit under test, and only
/// the evidence is uploaded (decision 31). Inputs reach the shell only as
/// env, validated. Maestro is pinned by version and sha256 and sends no usage
/// data. It runs on an emulator only, and every adb call names it.
void main() {
  final wf = File('.github/workflows/emulator.yaml').readAsStringSync();
  final run = File('tool/emulator/run.sh').readAsStringSync();

  test('manual or the "emulator" label only; read-only; no secrets', () {
    expect(wf, contains('  workflow_dispatch:\n'));
    expect(
      wf,
      contains('  pull_request:\n    types: [labeled, synchronize]\n'),
    );
    expect(wf, contains("github.event.label.name == 'emulator'"));
    expect(wf, isNot(contains('push:')));
    expect(wf, isNot(contains('pull_request_target')));
    expect(wf, isNot(contains('schedule:')));
    expect(wf, contains('\npermissions:\n  contents: read\n'));
    expect(wf, isNot(contains('secrets.')));
    // Three checkouts (this workflow, the app, the flows), none keeping a token.
    expect('uses: actions/checkout@'.allMatches(wf), hasLength(3));
    expect('persist-credentials: false'.allMatches(wf), hasLength(3));
  });

  // Job-level, not workflow-level: every push to any PR starts this
  // workflow, and a run whose job is skipped must not join the group (it
  // would displace a pending dispatch).
  test('one emulator at a time; a running one is never cancelled', () {
    expect(
      wf,
      contains(
        '\n    concurrency:\n      group: emulator\n'
        '      cancel-in-progress: false\n',
      ),
    );
    expect(wf, isNot(contains('\nconcurrency:')));
  });

  test('inputs reach the shell only as env, and are validated', () {
    final blocks = runBlocks(wf);
    expect(blocks.length, greaterThanOrEqualTo(6), reason: 'run steps found');
    for (final block in blocks) {
      expect(block, isNot(contains(r'${{')), reason: block);
    }
    for (final check in [
      r'[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]]',
      r'[[ "$FLOWS_REF" =~ ^[A-Za-z0-9._/-]{1,100}$ && "$FLOWS_REF" != *..* ]]',
      r'[[ "$TAGS" =~ ^[a-z0-9_-]+(,[a-z0-9_-]+)*$ ]]',
      r'[[ "$KIND" =~ ^(debug|reminder-now|release)$ ]]',
      r'[[ -z "$ROWS" || "$ROWS" =~ ^[a-z0-9_-]{1,40}$ ]]',
      r'[[ "$ZONE" =~ ^[A-Za-z_]+(/[A-Za-z0-9_+-]+){0,2}$ ]]',
    ]) {
      expect(wf, contains(check));
    }
    // A PR run: the PR's head, the smoke flows, the debug APK, UTC.
    expect(
      wf,
      contains(
        'HEAD_SHA=\$PR_HEAD FLOWS_REF=\$PR_HEAD TAGS=smoke KIND=debug ROWS= ZONE=UTC FAKE_NOW=',
      ),
    );
  });

  test('the scan for expressions in run steps sees one', () {
    const sample = '''
steps:
  - name: a
    run: |
      echo "\${{ inputs.x }}"
  - run: echo ok
  - name: b
    env:
      X: \${{ inputs.x }}
''';
    expect(runBlocks(sample), hasLength(2));
    expect(runBlocks(sample).first, contains(r'${{'));
    expect(runBlocks(sample).last, 'echo ok');
  });

  test('the APK is built in this job from head_sha; only evidence leaves', () {
    final checkout = wf.indexOf(r'ref: ${{ steps.in.outputs.head }}');
    expect(checkout, greaterThan(0));
    expect(wf.indexOf('flutter build apk'), greaterThan(checkout));
    // The APK sits outside the evidence folder.
    expect(
      wf,
      contains(
        r'cp "build/app/outputs/flutter-apk/$built" "$RUNNER_TEMP/under-test.apk"',
      ),
    );
    expect(wf, contains(r'OUT: ${{ runner.temp }}/evidence'));
    // The guard, then the only upload: the evidence, 3 days.
    final guard = wf.indexOf('- name: No installable file in the evidence');
    final upload = wf.indexOf('uses: actions/upload-artifact@');
    expect(guard, greaterThan(0));
    expect(upload, greaterThan(guard));
    expect('actions/upload-artifact'.allMatches(wf), hasLength(1));
    for (final ext in [
      'apk',
      'aab',
      'apks',
      'ipa',
      'dex',
      'jar',
      'so',
      'zip',
    ]) {
      expect(
        wf.substring(guard, upload),
        contains("-iname '*.$ext'"),
        reason: ext,
      );
    }
    final step = wf.substring(upload);
    expect(step, contains("steps.guard.outcome == 'success'"));
    expect(
      step,
      contains(
        r'path: ${{ runner.temp }}/evidence'
        '\n',
      ),
    );
    expect(step, contains('retention-days: 3\n'));
  });

  test('no env value is printed', () {
    expect(wf, contains(r'rm -f "$RUNNER_TEMP/defines.json"'));
    expect(wf, isNot(contains('cat "\$RUNNER_TEMP/defines.json"')));
    expect(wf, isNot(contains('cat env/')));
  });

  test('Maestro pinned by version and sha256, sending no usage data', () {
    expect(wf, contains('  MAESTRO_VERSION: 2.12.1\n'));
    expect(wf, contains(RegExp(r'  MAESTRO_SHA256: [0-9a-f]{64}\n')));
    expect(wf, contains(r'sha256sum -c -'));
    expect(wf, contains('  MAESTRO_CLI_NO_ANALYTICS: 1\n'));
  });

  test('Android 14 (API 34), the emulator action pinned by sha', () {
    expect(wf, contains('api-level: 34\n'));
    expect(wf, contains('target: google_apis\n'));
    expect(
      wf,
      contains(
        RegExp(
          r'uses: reactivecircus/android-emulator-runner@[0-9a-f]{40} # v\d',
        ),
      ),
    );
    expect(
      wf,
      contains(r'script: bash "$GITHUB_WORKSPACE/ci/tool/emulator/run.sh"'),
    );
  });

  // The first label run died at boot: "Not enough space to create userdata
  // partition" (3.5 GB left on /, 7.4 GB needed).
  test('room for the emulator: a 4 GB data partition, on the larger disk', () {
    expect(wf, contains('disk-size: 4096M\n'));
    expect(wf, contains(r'ln -sfn /mnt/avd "$HOME/.android/avd"'));
    final copy = wf.indexOf(r'cp "build/app/outputs/flutter-apk/$built"');
    expect(wf.indexOf('rm -rf build\n'), greaterThan(copy));
    expect(
      wf.indexOf('rm -rf build\n'),
      lessThan(wf.indexOf('android-emulator-runner@')),
    );
  });

  test('a failed step still leaves a reason in the evidence', () {
    final step = wf.indexOf(
      "- name: If a step failed, the disk and the emulator's setup",
    );
    expect(step, greaterThan(wf.indexOf('android-emulator-runner@')));
    expect(
      step,
      lessThan(wf.indexOf('- name: No installable file in the evidence')),
    );
    final body = wf.substring(
      step,
      wf.indexOf('- name: No installable file in the evidence'),
    );
    expect(body, contains(r'if: ${{ failure() }}'));
    expect(body, contains(r'> "$OUT/boot.txt"'));
  });

  test('run.sh: an emulator only, and every adb call names it', () {
    expect(run, contains('emulator-*) ;;'));
    expect(run, contains('ro.kernel.qemu'));
    expect(run, contains('ro.boot.qemu'));
    final code = run
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .toList();
    final adb = [
      for (final l in code)
        if (RegExp(r'(^|[^\w-])adb(\s|$)').hasMatch(l)) l.trim(),
    ];
    expect(adb, [r'A() { adb -s "$SERIAL" "$@"; }']);
  });

  test('run.sh: the zone, gesture navigation and en-US are checked', () {
    expect(run, contains('setprop persist.sys.timezone "\$ZONE"'));
    expect(run, contains('STOP: the zone is'));
    expect(run, contains('navbar.gestural'));
    expect(run, contains('STOP: the locale is'));
  });

  test(
    'run.sh: the installed APK is the one built; rows get APK + HEAD_SHA',
    () {
      expect(run, contains(r'A pull "$path" "$RUNNER_TEMP/installed.apk"'));
      expect(run, contains(r'[ "$installed" != "$built" ]'));
      expect(
        run,
        contains('export APK HEAD_SHA FLOWS_SHA OUT SERIAL APP_ID KIND\n'),
      );
      expect(run, contains(r'rows="$FLOWS_DIR/tool/device-rows/$ROWS.sh"'));
      expect(run, contains('--test-output-dir "\$OUT/maestro"'));
      // Relative outputs (takeScreenshot files) land in the evidence: the
      // script works from it before the rows or Maestro run.
      final cd = run.indexOf('\ncd "\$OUT"\n');
      expect(cd, greaterThan(0));
      expect(run.indexOf('bash "\$rows"'), greaterThan(cd));
      expect(run.indexOf('maestro --device'), greaterThan(cd));
    },
  );

  // Decision 45: the logcat is evidence only when a flow fails.
  test('run.sh: Maestro\'s logs are dropped only after every flow passed', () {
    expect(run, contains('set -euo pipefail\n'));
    final logs = run.indexOf(
      'find "\$OUT/maestro" -type d -name logs -prune -exec rm -rf {} +',
    );
    expect(logs, greaterThan(run.indexOf('maestro --device')));
    expect(run.substring(logs), isNot(contains('maestro --device')));
  });

  test('both commits are logged: the app built and the flows run', () {
    expect(wf, contains(r'FLOWS_REF: ${{ steps.in.outputs.flows }}'));
    expect(run, contains(r'FLOWS_SHA=$(git -C "$FLOWS_DIR" rev-parse HEAD)'));
    expect(run, contains(r'flows $FLOWS_REF = $FLOWS_SHA'));
  });

  test("the tester's smoke files are carried as they are", () {
    for (final f in [
      '.maestro/config.yaml',
      '.maestro/subflows/fresh_launch.yaml',
      '.maestro/flows/pb1/00_smoke_launch.yaml',
    ]) {
      expect(File(f).readAsStringSync(), isNot(contains('\r')), reason: f);
    }
    expect(
      File('.maestro/flows/pb1/00_smoke_launch.yaml').readAsStringSync(),
      contains('tags: [pb1, smoke]'),
    );
  });
}

/// The bodies of a workflow's `run:` steps, block or one-line.
List<String> runBlocks(String yaml) {
  final lines = yaml.split('\n');
  final blocks = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'^(\s*)(- )?run: ?(.*)$').firstMatch(lines[i]);
    if (m == null) continue;
    final indent = m.group(1)!.length + (m.group(2)?.length ?? 0);
    final rest = m.group(3)!;
    if (rest.isNotEmpty && rest != '|' && rest != '>') {
      blocks.add(rest);
      continue;
    }
    final body = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final l = lines[j];
      if (l.trim().isNotEmpty && l.length - l.trimLeft().length <= indent) {
        break;
      }
      body.add(l);
    }
    blocks.add(body.join('\n'));
  }
  return blocks;
}
