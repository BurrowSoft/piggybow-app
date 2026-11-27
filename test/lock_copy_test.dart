import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';
import 'package:piggybow/features/lock/lock_screen.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  test('Face ID or Touch ID only when the device says so', () {
    expect(lockUseLabel(en, BiometricKind.faceId), 'Use Face ID');
    expect(lockUseLabel(en, BiometricKind.touchId), 'Use Touch ID');
    expect(lockHintLabel(en, BiometricKind.faceId), contains('Face ID'));
    expect(lockHintLabel(en, BiometricKind.touchId), contains('Touch ID'));
  });

  test('neither set up, Android, or no answer yet: the general words', () {
    for (final kind in [BiometricKind.other, null]) {
      expect(lockUseLabel(en, kind), en.lockUseBiometrics);
      expect(lockHintLabel(en, kind), en.meAppLockHint);
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
