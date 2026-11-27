import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Play release build (decision 162): manual, from master, the prod
/// flavour, signed with the upload key from secrets only, and its
/// permissions exactly the data-safety list. These file checks keep it so.
void main() {
  final workflow = File('.github/workflows/release-aab.yaml')
      .readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final expected = File('android/expected-permissions.txt')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();

  // The Reviewer, 1.3.0: the tracker check runs in every release build,
  // after the build and before anything is uploaded.
  test('verifyNoTrackingDeps runs in the release build, before the upload', () {
    final check = workflow.indexOf(
      './gradlew --no-daemon verifyNoTrackingDeps',
    );
    expect(check, greaterThan(workflow.indexOf('flutter build appbundle')));
    expect(check, lessThan(workflow.indexOf('actions/upload-artifact')));
    expect(
      File('android/build.gradle.kts').readAsStringSync(),
      contains('tasks.register("verifyNoTrackingDeps")'),
    );
  });

  // 15 Nov: build 12 was killed twice for memory (the project's -Xmx8G on a
  // ~7 GB runner, then a second JVM beside the build's daemon).
  test('the release build fits the runner: capped heap, one Gradle JVM', () {
    final cap = workflow.indexOf("'org.gradle.jvmargs=-Xmx4g");
    expect(cap, greaterThan(0));
    expect(workflow, contains('>> ~/.gradle/gradle.properties'));
    expect(cap, lessThan(workflow.indexOf('flutter build appbundle')));
    final stop = workflow.indexOf('./gradlew --stop');
    expect(stop, greaterThan(workflow.indexOf('flutter build appbundle')));
    expect(
      stop,
      lessThan(workflow.indexOf('./gradlew --no-daemon verifyNoTrackingDeps')),
    );
    expect(
      workflow,
      contains(
        './gradlew --no-daemon verifyNoTrackingDeps -Dorg.gradle.jvmargs=-Xmx2g',
      ),
    );
  });

  // The Reviewer, round 3 B3: the R8 mapping is checked and kept with the AAB.
  // The repo is public: an artifact is downloadable by anyone signed in to
  // GitHub. Decision 31: two uploads only, each kept 3 days: the release AAB,
  // and the emulator job's evidence (never a build: emulator_workflow_test).
  // No workflow uploads an APK, the mapping or a report.
  test('two artifacts only, the AAB and the emulator evidence, 3 days each; R8 mapping checked first', () {
    const mapping = 'build/app/outputs/mapping/prodRelease/mapping.txt';
    final check = workflow.indexOf('M=$mapping');
    expect(check, greaterThan(workflow.indexOf('flutter build appbundle')));
    final upload = workflow.indexOf('actions/upload-artifact');
    expect(check, lessThan(upload));
    final step = workflow.substring(upload);
    expect(
      step,
      contains(
        'path: build/app/outputs/bundle/prodRelease/app-prod-release.aab\n',
      ),
    );
    expect(step, contains('retention-days: 3'));
    expect(step, isNot(contains('mapping.txt')));
    final uploads = {
      for (final f in Directory(
        '.github/workflows',
      ).listSync().whereType<File>())
        f.uri.pathSegments.last: 'actions/upload-artifact'
            .allMatches(f.readAsStringSync())
            .length,
    }..removeWhere((_, n) => n == 0);
    expect(uploads, {'release-aab.yaml': 1, 'emulator.yaml': 1});
  });

  test('manual only, from master, the prod flavour with its env', () {
    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, isNot(contains('pull_request')));
    expect(workflow, isNot(contains('push:')));
    expect(workflow, contains("if: github.ref != 'refs/heads/master'"));
    expect(
      workflow,
      contains(
        'flutter build appbundle --release --flavor prod \\\n'
        '            --dart-define-from-file=env/prod.json',
      ),
    );
  });

  test('the upload key only from secrets; checked and removed', () {
    for (final name in [
      'PIGGYBOW_UPLOAD_KEYSTORE_B64',
      'PIGGYBOW_UPLOAD_STORE_PASSWORD',
      'PIGGYBOW_UPLOAD_KEY_ALIAS',
      'PIGGYBOW_UPLOAD_KEY_PASSWORD',
    ]) {
      expect(workflow, contains('secrets.$name'), reason: name);
    }
    expect(workflow, contains("grep -q 'Owner: CN=Piggybow Upload'"));
    expect(workflow, contains('Android Debug'));
    expect(workflow, contains('rm -f "\$RUNNER_TEMP/upload.jks"'));
    // No key material in the repo.
    final keys = Directory('android')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => RegExp(r'\.(jks|keystore|p12)$').hasMatch(f.path))
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(keys, ['debug-shared.keystore']);
  });

  test(
    'gradle: the upload key from the environment; prod never debug-signed',
    () {
      expect(gradle, contains('System.getenv("PIGGYBOW_UPLOAD_KEYSTORE")'));
      expect(gradle, contains('signingConfigs.findByName("upload")'));
      expect(gradle, contains('it.name.contains("ProdRelease")'));
      expect(gradle, contains('throw GradleException('));
    },
  );

  test('the AAB permissions are diffed against the data-safety list', () {
    expect(workflow, contains('bundletool'));
    // Both forms aapt lists: a plugin could add either.
    expect(
      workflow,
      contains(
        "--xpath '/manifest/uses-permission/@android:name"
        " | /manifest/uses-permission-sdk-23/@android:name'",
      ),
    );
    // Inputs reach the shell as env, validated (no expression injection).
    expect(workflow, contains(r'[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]'));
    expect(workflow, isNot(contains(r'--build-number="${{')));
    expect(
      workflow,
      contains('diff <(sort android/expected-permissions.txt) permissions.txt'),
    );
    // v0.1: only what the reminder (notifications, boot), the app lock
    // (biometrics; USE_FINGERPRINT is androidx.biometric's fallback below
    // API 28) and crash reports (INTERNET) need, exactly these, sorted; plus
    // the Plus plumbing's BILLING and ACCESS_NETWORK_STATE from billing's
    // datatransport. No microphone, camera, health or location.
    expect(expected, [
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.INTERNET',
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.USE_BIOMETRIC',
      'android.permission.USE_FINGERPRINT',
      'android.permission.VIBRATE',
      'com.android.vending.BILLING',
      'com.burrowsoft.piggybow.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION',
    ]);
    expect(expected.join('\n'), isNot(contains('AD_ID')));
    expect(expected.join('\n'), isNot(contains('EXACT_ALARM')));
    // The Reviewer + UX, 14 Nov: play-services-location ships with Play
    // Billing; it can never read location, because no location permission
    // is in this exact-match list (fine, coarse or background).
    expect(expected.join('\n'), isNot(contains('LOCATION')));
    expect(expected.join('\n'), isNot(contains('RECORD_AUDIO')));
    expect(expected.join('\n'), isNot(contains('CAMERA')));
    expect(expected.join('\n'), isNot(contains('health')));
    // iOS: Face ID's purpose string (app-store-privacy.md, decision 171).
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      contains(
        '<key>NSFaceIDUsageDescription</key>\n'
        '\t<string>Unlock Piggybow with Face ID.</string>',
      ),
    );
  });

  test('16 KB alignment, the merged manifest, no sentry-native', () {
    expect(workflow, contains("readelf -lW"));
    expect(workflow, contains(r'-lt 16384'));
    expect(workflow, contains(r'"$ZIPALIGN" -c -P 16'));
    expect(workflow, contains('merged-manifest.xml'));
    expect(workflow, contains('native-libs.txt'));
    expect(
      gradle,
      contains('exclude(group = "io.sentry", module = "sentry-android-ndk")'),
    );
    // Native crash handling stays off, so nothing needs the NDK module.
    final sentry = File('lib/core/sentry_setup.dart').readAsStringSync();
    expect(sentry, contains('..enableNativeCrashHandling = false'));
    expect(sentry, contains('..enableNdkScopeSync = false'));
  });

  // The same list is diffed on every PR APK (the tester reads the facts from
  // the log): a plugin that adds a permission fails the PR, not the release.
  test('the PR APK: permissions diffed, badging and backup printed', () {
    final pr = File('.github/workflows/pr-apk.yaml').readAsStringSync();
    expect(
      pr,
      contains('diff <(sort android/expected-permissions.txt) permissions.txt'),
    );
    expect(pr, contains('dump badging'));
    expect(pr, contains('allowBackup'));
  });

  test('one Flutter version everywhere', () {
    final versions = {
      for (final f in Directory(
        '.github/workflows',
      ).listSync().whereType<File>())
        ...RegExp(r'flutter-version: (\S+)')
            .allMatches(f.readAsStringSync())
            .map((m) => m.group(1)),
    };
    expect(versions, hasLength(1));
  });
}
