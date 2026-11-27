import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Version 0.1 sends nothing, and the phone itself enforces it: a release
/// build asks for no network permission, a release that would need the
/// network (a crash-report DSN, or Plus with Play Billing) fails to build
/// until its manifest changes too, and nothing in the app fetches anything
/// at runtime. android/expected-permissions.txt is the release list that the
/// Play upload and CI's release manifest are diffed against.
void main() {
  final release = File('android/app/src/release/AndroidManifest.xml')
      .readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  List<String> lines(String path) =>
      File(path).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
  final expected = lines('android/expected-permissions.txt');
  final debugOnly = lines('android/debug-only-permissions.txt');

  test('a release build removes INTERNET and ACCESS_NETWORK_STATE', () {
    expect(release, contains('xmlns:tools="http://schemas.android.com/tools"'));
    for (final permission in ['INTERNET', 'ACCESS_NETWORK_STATE']) {
      expect(
        release,
        matches(
          RegExp(
            'android:name="android\\.permission\\.$permission"'
            '\\s+tools:node="remove"',
          ),
        ),
        reason: permission,
      );
    }
  });

  test('debug and profile builds keep INTERNET, for the Flutter tool', () {
    for (final type in ['debug', 'profile']) {
      expect(
        File('android/app/src/$type/AndroidManifest.xml').readAsStringSync(),
        contains('android:name="android.permission.INTERNET"'),
        reason: type,
      );
    }
  });

  test('the release list has no network; the debug list adds just that', () {
    expect(expected, isNot(contains('android.permission.INTERNET')));
    expect(
      expected,
      isNot(contains('android.permission.ACCESS_NETWORK_STATE')),
    );
    expect(debugOnly, [
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.INTERNET',
    ]);
    expect(expected.toSet().intersection(debugOnly.toSet()), isEmpty);
  });

  test('a release build that would need the network stops', () {
    expect(gradle, contains('project.findProperty("dart-defines")'));
    expect(gradle, contains('java.util.Base64.getDecoder()'));
    expect(gradle, contains('it.name.contains("Release")'));
    expect(gradle, contains('dartDefines["SENTRY_DSN"]'));
    expect(gradle, contains('dartDefines["PLUS_ENABLED"] == "true"'));
    expect(gradle, contains('if (release && (dsn || plus))'));
    // And no build of v0.1 sets either: every env file a build reads.
    final envs = Directory('env')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    expect(envs, hasLength(3));
    for (final f in envs) {
      final env = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect('${env['SENTRY_DSN'] ?? ''}'.trim(), isEmpty, reason: f.path);
      expect('${env['PLUS_ENABLED']}', isNot('true'), reason: f.path);
    }
  });

  test("CI diffs the release manifest's permissions against the list", () {
    final ci = File('.github/workflows/ci.yaml').readAsStringSync();
    expect(ci, contains(':app:processStagingReleaseMainManifest'));
    expect(
      ci,
      contains(
        r'diff <(sort expected-permissions.txt) "$RUNNER_TEMP/release-permissions.txt"',
      ),
    );
    final pr = File('.github/workflows/pr-apk.yaml').readAsStringSync();
    expect(pr, contains('android/debug-only-permissions.txt'));
  });

  test('nothing in the app fetches from the network', () {
    // No network package; the fonts are bundled assets.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final package in [
      'http',
      'dio',
      'google_fonts',
      'cached_network_image',
      'webview_flutter',
      'flutter_cache_manager',
      'connectivity_plus',
      'firebase_core',
    ]) {
      expect(
        RegExp('^\\s+$package:', multiLine: true).hasMatch(pubspec),
        isFalse,
        reason: package,
      );
    }
    expect(pubspec, contains('asset: assets/fonts/Poppins-Regular.ttf'));
    // No network call in the app's own code.
    final calls = RegExp(
      r'Image\.network|NetworkImage|SvgPicture\.network|HttpClient\(|'
      r'package:http/|package:dio/|WebView',
    );
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              !f.path.replaceAll('\\', '/').contains('/l10n/gen/'),
        )
        .toList();
    expect(sources, isNotEmpty);
    for (final f in sources) {
      expect(calls.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('the signing secrets: line endings stripped, whitespace fails', () {
    final workflow = File('.github/workflows/release-aab.yaml')
        .readAsStringSync();
    expect(
      workflow,
      contains(
        r'''KEYSTORE_B64=$(printf '%s' "$KEYSTORE_B64" | tr -d '\r\n')''',
      ),
    );
    expect(workflow, contains(r'if [[ "$KEYSTORE_B64" =~ [[:space:]] ]]'));
    // Both steps that read the alias and passwords clean them first.
    const loop =
        'for v in PIGGYBOW_UPLOAD_STORE_PASSWORD PIGGYBOW_UPLOAD_KEY_ALIAS '
        'PIGGYBOW_UPLOAD_KEY_PASSWORD; do';
    expect(loop.allMatches(workflow), hasLength(2));
    expect(
      r'''val=$(printf '%s' "${!v}" | tr -d '\r\n')'''.allMatches(workflow),
      hasLength(2),
    );
    expect(r'echo "::add-mask::$val"'.allMatches(workflow), hasLength(2));
    final build = workflow.indexOf('flutter build appbundle');
    final bundletool = workflow.indexOf('build-apks --mode=universal');
    final loops = [for (final m in loop.allMatches(workflow)) m.start];
    expect(loops.first, lessThan(build));
    expect(loops.last, lessThan(bundletool));
    expect(loops.last, greaterThan(build));
    // The certificate check stays: the upload key's owner by name.
    expect(workflow, contains("grep -q 'Owner: CN=Piggybow Upload'"));
    // Piggybow's own rules in the header, no older project's.
    expect(workflow, isNot(contains('decision 162')));
    expect(workflow, isNot(contains('pilot')));
  });
}
