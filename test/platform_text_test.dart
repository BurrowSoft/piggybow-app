import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/l10n/platform_text.dart';

import 'helpers.dart';

/// Apple guideline 2.3.10, deny by default: an iPhone never shows another
/// platform's names. Every string is scanned. Only the keys listed here,
/// each with its reason, may name one; each has an iPhone twin (its key +
/// "Ios") that names none; and each is read in lib/ only through its chooser
/// in lib/l10n/platform_text.dart. The App Store page and piggybow.com's
/// linked pages are checked by hand.
const androidOnly = {
  'privacy1': "names Google's backup and Android's end-to-end rule",
  'meAppLockHint': "a fingerprint: Android's general words for its lock",
  'lockUseBiometrics': "a fingerprint: Android's general words for its lock",
};

/// Chosen by platform too, for the iPhone's own word (passcode, not screen
/// lock), though they name nothing banned.
const platformWorded = {
  'lockForgotBodyDevice',
  'lockForgotUseDevice',
  'lockForgotBodyEraseOnly',
};

/// Another platform, its store, its keyboard or its phones, as words; and a
/// fingerprint, which an iPhone with Face ID doesn't have.
final banned = RegExp(r'\b(Google|Android|Play|Gboard|Galaxy|Pixel)\b');
final fingerprint = RegExp('fingerprint', caseSensitive: false);
bool namesAnotherPlatform(String text) =>
    banned.hasMatch(text) || fingerprint.hasMatch(text);

void main() {
  final arb =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  final messages = {
    for (final e in arb.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
  final en = lookupAppLocalizations(const Locale('en'));

  test('the scan catches each word (control)', () {
    for (final s in [
      'Google',
      'on Android',
      'Google Play',
      'Gboard',
      'a Galaxy',
      'Pixel',
      'Use fingerprint',
      'Fingerprint',
    ]) {
      expect(namesAnotherPlatform(s), isTrue, reason: s);
    }
    for (final s in ['iCloud', 'display', 'to play', 'Face ID', 'passcode']) {
      expect(namesAnotherPlatform(s), isFalse, reason: s);
    }
  });

  test('only the listed keys name another platform, each with a reason', () {
    final naming = {
      for (final e in messages.entries)
        if (namesAnotherPlatform(e.value)) e.key,
    };
    expect(
      naming.difference(androidOnly.keys.toSet()),
      isEmpty,
      reason:
          'a string an iPhone could show names another platform: add an '
          'iPhone twin, its chooser in platform_text.dart and its reason here',
    );
    for (final key in androidOnly.keys) {
      expect(messages, contains(key), reason: 'listed but gone: $key');
    }
  });

  test("each has an iPhone twin that names no other platform", () {
    for (final key in [...androidOnly.keys, ...platformWorded]) {
      final twin = messages['${key}Ios'];
      expect(twin, isNotNull, reason: '${key}Ios');
      expect(namesAnotherPlatform(twin!), isFalse, reason: '${key}Ios');
    }
  });

  test('each is read in lib/ only through its chooser', () {
    final keys = [...androidOnly.keys, ...platformWorded];
    final read = RegExp('\\.(${keys.join('|')})\\b');
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.contains('lib/l10n/gen/') ||
          path.endsWith('lib/l10n/platform_text.dart')) {
        continue;
      }
      final hit = read.firstMatch(file.readAsStringSync());
      expect(hit, isNull, reason: '$path reads ${hit?.group(0)} directly');
    }
  });

  test("on an iPhone the choosers give the twins; elsewhere, Android's", () {
    expect(privacyStorage(en, TargetPlatform.iOS), en.privacy1Ios);
    expect(privacyStorage(en, TargetPlatform.android), en.privacy1);
    expect(en.privacy1Ios, contains('iCloud'));
    expect(
      en.privacy1Ios,
      isNot(contains('if you')),
      reason: 'not in any iPhone backup: no condition (decision 72, I-1(b))',
    );
  });

  testWidgets("an iPhone's Privacy screen names no other platform", (
    tester,
  ) async {
    final app = TestApp();
    await tester.runAsync(app.openJournal);
    await app.pump(tester);
    await tester.tapId('tab-me');
    await tester.tapId('me-privacy');
    tester.expectScreen('me-privacy-screen');
    final shown = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        t.data ?? t.textSpan?.toPlainText() ?? '',
    ];
    expect(shown, contains(en.privacy1Ios));
    for (final s in shown) {
      expect(namesAnotherPlatform(s), isFalse, reason: s);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
