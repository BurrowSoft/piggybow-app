import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/l10n/platform_text.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  const android = TargetPlatform.android;
  const iPhone = TargetPlatform.iOS;

  test('Face ID or Touch ID only when the device says so', () {
    for (final p in [android, iPhone]) {
      expect(lockUseLabel(en, BiometricKind.faceId, p), 'Use Face ID');
      expect(lockUseLabel(en, BiometricKind.touchId, p), 'Use Touch ID');
      expect(lockHintLabel(en, BiometricKind.faceId, p), contains('Face ID'));
      expect(lockHintLabel(en, BiometricKind.touchId, p), contains('Touch ID'));
    }
  });

  test('neither set up, or no answer yet: the general words on Android', () {
    for (final kind in [BiometricKind.other, null]) {
      expect(lockUseLabel(en, kind, android), en.lockUseBiometrics);
      expect(lockHintLabel(en, kind, android), en.meAppLockHint);
    }
  });

  test("an iPhone's own words, never a fingerprint (Apple 2.3.10)", () {
    for (final kind in [BiometricKind.other, null]) {
      expect(lockUseLabel(en, kind, iPhone), en.lockUseBiometricsIos);
      expect(lockHintLabel(en, kind, iPhone), en.meAppLockHintIos);
      expect(lockUseLabel(en, kind, iPhone), isNot(contains('fingerprint')));
      expect(lockHintLabel(en, kind, iPhone), isNot(contains('fingerprint')));
    }
  });

  test("Forgot PIN: the phone's screen lock, or the iPhone's passcode", () {
    expect(lockForgotBodyDevice(en, android), en.lockForgotBodyDevice);
    expect(lockForgotUseDevice(en, android), en.lockForgotUseDevice);
    expect(lockForgotBodyEraseOnly(en, android), en.lockForgotBodyEraseOnly);
    for (final text in [
      lockForgotBodyDevice(en, iPhone),
      lockForgotUseDevice(en, iPhone),
      lockForgotBodyEraseOnly(en, iPhone),
    ]) {
      expect(text, contains('passcode'));
      expect(text, isNot(contains('screen lock')));
    }
  });

  test('the system\'s names stay as they are in every language', () {
    for (final code in ['en']) {
      final l = lookupAppLocalizations(Locale(code));
      expect(l.lockUseFaceId, contains('Face ID'), reason: code);
      expect(l.lockUseTouchId, contains('Touch ID'), reason: code);
      expect(l.meAppLockHintFaceId, contains('Face ID'), reason: code);
      expect(l.meAppLockHintTouchId, contains('Touch ID'), reason: code);
    }
  });
}
