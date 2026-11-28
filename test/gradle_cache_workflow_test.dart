import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gradle's downloads are cached, since Maven Central answers busy runners
/// with 429s. Only ci.yaml saves: on master from merged code, on a PR into
/// that PR's own scope. The emulator, PR APK and release workflows restore
/// only, so neither a run that builds a PR's code nor a release ever writes a
/// cache that a release could read.
void main() {
  final workflows = {
    for (final f in Directory('.github/workflows').listSync().whereType<File>())
      if (f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
        f.uri.pathSegments.last: f.readAsStringSync(),
  };

  test('only ci.yaml saves a Gradle cache: its trackers and apk jobs', () {
    for (final w in workflows.entries) {
      final saves = 'uses: actions/cache@'.allMatches(w.value).length;
      expect(saves, w.key == 'ci.yaml' ? 2 : 0, reason: w.key);
    }
  });

  test('the emulator, PR APK and release workflows restore only, from the apk job', () {
    for (final name in ['emulator.yaml', 'pr-apk.yaml', 'release-aab.yaml']) {
      final wf = workflows[name]!;
      expect('uses: actions/cache/restore@'.allMatches(wf), hasLength(1), reason: name);
      expect(wf, contains(r'key: gradle-${{ runner.os }}-apk-'), reason: name);
    }
  });

  test("setup-java's own Gradle cache is gone: nothing else saves ~/.gradle", () {
    for (final w in workflows.entries) {
      expect(w.value, isNot(contains('cache: gradle')), reason: w.key);
    }
  });

  test('every key covers the Gradle files, the wrapper and pubspec.lock', () {
    final keys = [
      for (final w in workflows.values)
        for (final m in RegExp(r'^\s*key: (gradle-.+)$', multiLine: true).allMatches(w)) m[1]!,
    ];
    expect(keys, hasLength(5));
    for (final k in keys) {
      for (final part in ['android/**/*.gradle*', 'android/gradle/wrapper/gradle-wrapper.properties', 'pubspec.lock']) {
        expect(k, contains(part), reason: k);
      }
    }
  });
}
