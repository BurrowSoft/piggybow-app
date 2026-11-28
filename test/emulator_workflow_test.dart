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
      r'[[ "$KIND" =~ ^(debug|reminder-now|release|prod-release|plus-rows|plus-owned|plus-probe)$ ]]',
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
      'jks',
      'p12',
      'keystore',
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

  // The store's build on the emulator (decision 64): the prod flavour in
  // release with R8 and env/prod.json, signed with a key made in the job and
  // deleted after the build, never the upload key; the flows drive the
  // store's package; no fixed clock.
  test('prod-release: the store build, with a throwaway key', () {
    expect(
      wf,
      contains(
        'options: [debug, reminder-now, release, prod-release, plus-rows, plus-owned, plus-probe]',
      ),
    );
    expect(wf, contains(r'[[ "$KIND" != prod-release || -z "$FAKE_NOW" ]]'));
    expect(
      wf,
      contains(
        'if [ "\$KIND" = prod-release ]; then APP_ID=com.burrowsoft.piggybow; '
        'else APP_ID=com.burrowsoft.piggybow.staging; fi',
      ),
    );
    expect(wf, contains(r'APP_ID: ${{ steps.in.outputs.app_id }}'));
    final build = wf.substring(
      wf.indexOf('- name: Build the APK under test'),
      wf.indexOf('- name: Maestro'),
    );
    final trap = build.indexOf(
      r'''trap 'rm -f "$RUNNER_TEMP/throwaway.jks"' EXIT''',
    );
    final keytool = build.indexOf('keytool -genkeypair');
    expect(trap, greaterThan(0));
    expect(keytool, greaterThan(trap));
    expect(build, contains(r'pass=$(openssl rand -hex 16)'));
    // The throwaway password is masked before anything could print it.
    final mask = build.indexOf(r'echo "::add-mask::$pass"');
    expect(mask, greaterThan(build.indexOf(r'pass=$(openssl rand -hex 16)')));
    expect(keytool, greaterThan(mask));
    expect(build, contains('-dname "CN=Piggybow CI throwaway"'));
    expect(wf, isNot(contains('Piggybow Upload')));
    expect(build, contains(r'cp env/prod.json "$RUNNER_TEMP/defines.json"'));
    final prodBuild = build.indexOf(
      r'flutter build apk --release --flavor prod --dart-define-from-file="$RUNNER_TEMP/defines.json"',
    );
    expect(prodBuild, greaterThan(keytool));
    expect(
      build.indexOf(r'rm -f "$RUNNER_TEMP/throwaway.jks"', prodBuild),
      greaterThan(prodBuild),
    );
    expect(build, contains('built=app-prod-release.apk'));
    // The installed app's permissions go into the evidence, for the rows.
    final installed = run.indexOf(r'echo "installed = built ($installed)"');
    final perms = run.indexOf(
      r'grep -A30 "requested permissions" <<< "$pkg" > "$OUT/permissions.txt"',
    );
    expect(perms, greaterThan(installed));
    expect(run.indexOf('maestro --device'), greaterThan(perms));
  });

  // Decision 79: Plus on the emulator, in its three staging kinds only. The
  // tester's rows get the rows' fake store (debug builds), owning Plus in
  // plus-owned; the probe gets
  // the real Play Billing layer in a profile build without the network-state
  // permission, as the store build will be, on a Play Store image.
  test('plus-rows, plus-owned and plus-probe: Plus only in their staging builds; the '
      "probe's manifest change in the runner only", () {
    final build = wf.substring(
      wf.indexOf('- name: Build the APK under test'),
      wf.indexOf('- name: Maestro'),
    );
    final prod = build.substring(
      build.indexOf('if [ "\$KIND" = prod-release ]; then'),
      build.indexOf('          else\n'),
    );
    expect(prod, isNot(contains('PLUS')), reason: "the store's build never has Plus");
    expect(
      build,
      contains(
        r'| if $kind == "plus-rows" or $kind == "plus-owned" or $kind == "plus-probe" then .PLUS_ENABLED = "true" else . end',
      ),
    );
    expect(
      build,
      contains(
        r'| if $kind == "plus-rows" or $kind == "plus-owned" then .PLUS_FAKE_STORE = "true" else . end',
      ),
    );
    expect(
      build,
      contains(r'| if $kind == "plus-owned" then .PLUS_ROWS_OWNED = "true" else . end'),
    );
    expect('PLUS_ENABLED = '.allMatches(wf), hasLength(1));
    expect('PLUS_FAKE_STORE = '.allMatches(wf), hasLength(1));
    expect('PLUS_ROWS_OWNED = '.allMatches(wf), hasLength(1));
    // plus-rows and plus-owned are debug builds (the fake store also needs
    // kDebugMode).
    expect(build, contains('*) mode=--debug; built=app-staging-debug.apk ;;'));
    // The store build's permissions: the release overlay becomes this
    // runner's profile overlay, checked byte for byte.
    final probe = build.substring(build.indexOf('plus-probe)\n'));
    expect(
      probe,
      contains(
        'cp android/app/src/release/AndroidManifest.xml android/app/src/profile/AndroidManifest.xml\n'
        '                cmp -s android/app/src/release/AndroidManifest.xml android/app/src/profile/AndroidManifest.xml\n'
        '                mode=--profile; built=app-staging-profile.apk ;;',
      ),
    );
    // Never committed: the repo's profile overlay keeps INTERNET for the
    // Flutter tool, and removes nothing.
    final profile = File('android/app/src/profile/AndroidManifest.xml').readAsStringSync();
    expect(profile, contains('android.permission.INTERNET'));
    expect(profile, isNot(contains('tools:node="remove"')));
    // The probe reads the app's own expected permissions.
    expect(wf, contains(r'APP_DIR: ${{ github.workspace }}/app' '\n'));
    // The probe runs before run.sh's device set-up (adb root, which a Play
    // Store image lacks), after the emulator check.
    final branch = run.indexOf('if [ "\$KIND" = plus-probe ]; then');
    expect(branch, greaterThan(run.indexOf('ro.boot.qemu')));
    expect(branch, lessThan(run.indexOf('setprop persist.sys.timezone')));
    expect(run, contains(r'bash "$(dirname "$0")/plus_probe.sh"'));
  });

  test("plus_probe.sh: every adb call names the emulator; the app checked, "
      'and only the lines that matter kept', () {
    final probe = File('tool/emulator/plus_probe.sh').readAsStringSync();
    expect(probe, contains('set -Eeuo pipefail\n'));
    // A failed command never reads as "the app died": 8 while setting up,
    // 9 while reading the result.
    final setup = probe.indexOf(
      '''trap 'echo "STOP: a set-up step failed (line \$LINENO)"; exit 8' ERR''',
    );
    final install = probe.indexOf(r'A install "$APK"');
    final launch = probe.indexOf('A shell monkey');
    final reading = probe.indexOf(
      '''trap 'echo "STOP: reading the result failed (line \$LINENO)"; exit 9' ERR''',
    );
    expect(setup, greaterThan(0));
    expect(install, greaterThan(setup));
    expect(launch, greaterThan(install));
    expect(reading, greaterThan(launch));
    expect(probe.indexOf('A logcat -d'), greaterThan(reading));
    // Exactly the store build's permissions, or no probe.
    expect(probe, contains(r'"$APP_DIR/android/expected-permissions.txt"'));
    expect(probe, contains(r'if ! diff -u "$RUNNER_TEMP/expected.txt" "$OUT/permissions.txt"; then'));
    expect(probe, contains("STOP: the permissions aren't the store build's\"; exit 7"));
    final code = probe
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('#'))
        .toList();
    final adb = [
      for (final l in code)
        if (RegExp(r'(^|[^\w-])adb(\s|$)').hasMatch(l)) l.trim(),
    ];
    expect(adb, [r'A() { adb -s "$SERIAL" "$@"; }']);
    expect(probe, contains(r'[ "$installed" != "$built" ]'));
    expect(probe, contains('STOP: no Play Store app on this image'));
    // The whole log stays on the runner; the evidence is its filtered lines.
    expect(probe, contains(r'rm -f "$RUNNER_TEMP/logcat.txt"'));
    expect(probe, contains(r'> "$OUT/probe-logcat.txt"'));
    expect(probe, isNot(contains(r'> "$OUT/logcat')));
    expect(probe, contains('PROBE: the app did not stay up"; exit 1'));
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
    // The image: google_apis, or the Play Store image for the Plus probe
    // only, from the validated kind.
    expect(wf, contains(r'target: ${{ steps.in.outputs.target }}' '\n'));
    expect(
      wf,
      contains(
        'if [ "\$KIND" = plus-probe ]; then TARGET=google_apis_playstore; '
        'else TARGET=google_apis; fi',
      ),
    );
    expect('google_apis_playstore'.allMatches(wf), hasLength(1));
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

  // The first journal run's upload failed: a flow name with quotes became a
  // Maestro folder name, and artifact paths can't hold " : < > | * ?.
  test('evidence names are made safe for the upload, before the guard', () {
    final guard = wf.indexOf('- name: No installable file in the evidence');
    final upload = wf.indexOf('uses: actions/upload-artifact@');
    final step = wf.substring(guard, upload);
    final rename = step.indexOf(
      "find \"\$OUT\" -depth -name '*[\":<>|*?]*' -print0",
    );
    expect(rename, greaterThan(0));
    expect(step, contains("tr '\":<>|*?' '_______'"));
    // A clash fails the step; nothing is overwritten.
    expect(step, contains(r'if [ -e "$to" ]; then echo'));
    expect(step, contains(r'mv -n -- "$p" "$to"'));
    expect(rename, lessThan(step.indexOf("-iname '*.apk'")));
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
    // adbd can drop the first connection while it restarts as root: one
    // more try once the device is back, and a second failure still stops.
    expect(
      run,
      contains(
        '  A root >/dev/null || { sleep 3; A wait-for-device; A root >/dev/null; }\n'
        '  A wait-for-device\n',
      ),
    );
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
