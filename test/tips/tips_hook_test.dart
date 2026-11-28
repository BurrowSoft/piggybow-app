import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/policy.dart';
import 'package:piggybow/tips/tips_endpoint.dart';

/// The tester's mock tips server, fenced like the launch fixtures: a
/// staging debug build reads TIPS_TEST_URL, in one place; nothing else does.
/// Cleartext only to the emulator's host, only in debug builds. Otherwise
/// the endpoint is the tips project: HTTPS, with its publishable key.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('kTipsTestHook: false here, and true only in a staging debug build', () {
    expect(kTipsTestHook, isFalse);
    expect(
      read('lib/tips/tips_endpoint.dart'),
      contains("const kTipsTestHook = appFlavor == 'staging' && kDebugMode;"),
    );
  });

  // The texts gate: a release build offers pig tips only once their texts
  // are final (the consent sheet's AI and 18+ versions), whatever its env
  // file says; prod's env turns them on only with those texts and its key.
  test('pig tips in a release build only once their texts are final', () {
    expect(
      read('lib/core/app_config.dart'),
      contains(
        "aiTipsEnabled: const bool.fromEnvironment('AI_TIPS_ENABLED') && "
        '(!kReleaseMode || PolicyVersions.aiTextsFinal),',
      ),
    );
    expect("fromEnvironment('AI_TIPS_ENABLED')".allMatches(read('lib/core/app_config.dart')), hasLength(1));
    expect(read('lib/core/policy.dart'), contains("static const aiTextsFinal = ai != '' && age18 != '';"));
    expect(PolicyVersions.aiTextsFinal, PolicyVersions.ai.isNotEmpty && PolicyVersions.age18.isNotEmpty);
    final prod = jsonDecode(read('env/prod.json')) as Map<String, dynamic>;
    if (prod['AI_TIPS_ENABLED'] == 'true') {
      expect(PolicyVersions.aiTextsFinal, isTrue, reason: 'the texts first');
      expect('${prod['TIPS_ANON_KEY']}', startsWith('sb_publishable_'), reason: "prod's publishable key");
    }
  });

  // One source for the consent versions: the sheet records the ones the
  // release gate waits for, never a version of its own, and it's the only
  // place tips are turned on.
  test('the consent sheet records PolicyVersions.ai and .age18, with no version literal', () {
    final sheet = read('lib/features/tips/tips_ui.dart');
    expect(sheet, contains('aiVersion: PolicyVersions.ai,'));
    expect(sheet, contains('age18Version: PolicyVersions.age18,'));
    expect(RegExp(r'''['"](ai|age18)[-_]''').hasMatch(sheet), isFalse, reason: 'a version literal');
    expect(RegExp(r'''Version: ['"]''').hasMatch(sheet), isFalse, reason: 'a version literal');
    final turnsOn = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().contains('.turnOn('))
          f.path.replaceAll('\\', '/'),
    ];
    expect(turnsOn, ['lib/features/tips/tips_ui.dart']);
  });

  test('TIPS_TEST_URL is read once in the app, inside if (kTipsTestHook)', () {
    final readers = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && f.readAsStringSync().contains('TIPS_TEST_URL'))
          f.path.replaceAll('\\', '/'),
    ];
    expect(readers, ['lib/tips/tips_endpoint.dart']);
    final source = read('lib/tips/tips_endpoint.dart');
    const define = "String.fromEnvironment('TIPS_TEST_URL')";
    expect(define.allMatches(source), hasLength(1));
    final gate = source.indexOf('    if (kTipsTestHook) {\n');
    final close = source.indexOf('\n    }\n', gate);
    final at = source.indexOf(define);
    expect(gate, greaterThan(0));
    expect(at > gate && at < close, isTrue, reason: 'read only inside the gate');
  });

  test('cleartext only to 10.0.2.2, and only in debug builds', () {
    final config = read('android/app/src/debug/res/xml/network_security_config.xml');
    expect(config, contains('<base-config cleartextTrafficPermitted="false" />'));
    expect('<domain '.allMatches(config), hasLength(1));
    expect(config, contains('<domain includeSubdomains="false">10.0.2.2</domain>'));
    expect(
      read('android/app/src/debug/AndroidManifest.xml'),
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    // Every other source set (main, the build types, the flavours): a
    // flavour's files reach its release builds too.
    final sets = [
      for (final d in Directory('android/app/src').listSync().whereType<Directory>())
        d.path.replaceAll('\\', '/').split('/').last,
    ]..remove('debug');
    expect(sets, containsAll(['main', 'profile', 'release']));
    for (final set in sets) {
      final dir = 'android/app/src/$set';
      final manifest = File('$dir/AndroidManifest.xml');
      if (manifest.existsSync()) {
        final text = manifest.readAsStringSync();
        expect(text, isNot(contains('networkSecurityConfig')), reason: set);
        expect(text, isNot(contains('usesCleartextTraffic')), reason: set);
      }
      expect(File('$dir/res/xml/network_security_config.xml').existsSync(), isFalse, reason: set);
    }
  });

  test('the endpoint: the tips project over HTTPS with its key, or none', () {
    AppConfig config({String url = 'https://abc.supabase.co', String key = 'sb_publishable_x'}) =>
        AppConfig(flavor: Flavor.staging, tipsUrl: url, tipsAnonKey: key, tipsRegion: 'ap-northeast-1');
    final ok = TipsEndpoint.fromConfig(config())!;
    expect(ok.base, Uri.parse('https://abc.supabase.co'));
    expect(ok.publishableKey, 'sb_publishable_x');
    expect(ok.region, 'ap-northeast-1');
    expect(ok.mock, isFalse);
    expect(ok.at('/functions/v1/pig-tip'), Uri.parse('https://abc.supabase.co/functions/v1/pig-tip'));
    expect(
      ok.at('/auth/v1/token?grant_type=refresh_token'),
      Uri.parse('https://abc.supabase.co/auth/v1/token?grant_type=refresh_token'),
    );
    expect(TipsEndpoint.fromConfig(config(url: 'http://abc.supabase.co')), isNull, reason: 'HTTPS only');
    expect(TipsEndpoint.fromConfig(config(url: '')), isNull);
    expect(TipsEndpoint.fromConfig(config(key: '')), isNull);
  });
}
