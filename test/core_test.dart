import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_config.dart';
import 'package:piggybow/core/clock.dart';

void main() {
  test('unknown or missing flavor falls back to dev, never prod', () {
    expect(Flavor.parse('prod'), Flavor.prod);
    expect(Flavor.parse('staging'), Flavor.staging);
    expect(Flavor.parse(''), Flavor.dev);
    expect(Flavor.parse('production'), Flavor.dev);
  });

  test('the native --flavor wins and a mismatched env file fails fast', () {
    expect(
      Flavor.resolve(nativeFlavor: 'prod', envFlavor: 'prod'),
      Flavor.prod,
    );
    expect(
      Flavor.resolve(nativeFlavor: 'staging', envFlavor: ''),
      Flavor.staging,
    );
    expect(
      Flavor.resolve(nativeFlavor: null, envFlavor: 'staging'),
      Flavor.staging,
    );
    expect(
      () => Flavor.resolve(nativeFlavor: 'prod', envFlavor: 'staging'),
      throwsStateError,
    );
  });

  test('a fixed clock returns the pinned instant', () {
    final pinned = DateTime.parse('2026-10-02T08:30:00+07:00');
    expect(Clock(fixed: pinned).nowUtc().isAtSameMomentAs(pinned), isTrue);
  });

  test('the default clock follows real time', () {
    final before = DateTime.now();
    final now = Clock().nowUtc();
    expect(now.isBefore(before), isFalse);
  });

  test('"today" is the user\'s stored zone, not the phone\'s', () {
    // 01:30 UTC on Friday 2 October 2026.
    final clock = Clock(fixed: DateTime.utc(2026, 10, 2, 1, 30));
    expect(clock.todayIn('Asia/Bangkok'), DateTime(2026, 10, 2));
    expect(clock.nowIn('Asia/Bangkok').hour, 8);
    expect(clock.todayIn('Pacific/Pago_Pago'), DateTime(2026, 10, 1));
    expect(clock.todayIn('America/Sao_Paulo'), DateTime(2026, 10, 1));
    expect(clock.todayIn('Pacific/Kiritimati'), DateTime(2026, 10, 2));
    expect(clock.todayIn('Mars/Olympus'), DateTime(2026, 10, 2), reason: 'UTC');
    expect(wireDate(clock.todayIn('Pacific/Pago_Pago')), '2026-10-01');
  });

  Map<String, dynamic> env(String flavor) =>
      jsonDecode(File('env/$flavor.json').readAsStringSync())
          as Map<String, dynamic>;

  // v0.1 runs on the phone only (no account, no server): no env file may
  // carry a backend, and none may ever hold a secret.
  test('the env files: no backend, no secret, no DSN, no page links yet', () {
    for (final flavor in ['dev', 'staging', 'prod']) {
      final text = File('env/$flavor.json').readAsStringSync();
      final e = env(flavor);
      expect(e['FLAVOR'], flavor);
      for (final key in e.keys) {
        expect(key, isNot(startsWith('SUPABASE_')), reason: '$flavor: $key');
      }
      expect(e.containsKey('REGION_HOST'), isFalse, reason: flavor);
      expect(e.containsKey('WEB_ORIGIN'), isFalse, reason: flavor);
      expect(text, isNot(contains('sb_secret_')), reason: flavor);
      expect(text, isNot(contains('sb_publishable_')), reason: flavor);
      expect(text, isNot(contains('service_role')), reason: flavor);
      expect(text, isNot(contains('supabase.co')), reason: flavor);
      expect(text, isNot(contains('sentry.io')), reason: flavor);
      // No Sentry project yet: crash reports are off in every build.
      expect(e['SENTRY_DSN'], isEmpty, reason: flavor);
      // Links appear only once each page is live (a link never 404s).
      expect(e['PRIVACY_URL'], isEmpty, reason: flavor);
      expect(e['SUPPORT_URL'], isEmpty, reason: flavor);
      expect(e['TERMS_URL'], isEmpty, reason: flavor);
    }
  });

  test('dev and staging have the same keys; prod has no test hooks', () {
    final dev = env('dev'), staging = env('staging'), prod = env('prod');
    expect(dev.keys.toSet(), staging.keys.toSet());
    expect(
      prod.keys.toSet(),
      staging.keys.toSet().difference({'DISABLE_ANIMATIONS', 'FAKE_NOW'}),
    );
  });

  test('English only in v0.1: no other language is offered anywhere', () {
    for (final flavor in ['dev', 'staging', 'prod']) {
      final e = env(flavor);
      for (final key in e.keys.where((k) => k.endsWith('_OFFERED'))) {
        expect(e[key], 'false', reason: '$flavor: $key');
      }
    }
    expect(
      const AppConfig(flavor: Flavor.prod).shippedLocaleCodes(['en', 'th']),
      ['en'],
    );
  });

  test('the debug-only defines are in no env file or build workflow', () {
    for (final path in [
      for (final f in ['prod', 'staging', 'dev']) 'env/$f.json',
      '.github/workflows/release-aab.yaml',
      '.github/workflows/pr-apk.yaml',
      'codemagic.yaml',
    ]) {
      final text = File(path).readAsStringSync();
      expect(text, isNot(contains('QUICK_REMINDER_NOW')), reason: path);
      expect(text, isNot(contains('PLUS_FAKE_STORE')), reason: path);
    }
  });
}
