import 'package:flutter/foundation.dart' show TargetPlatform;

import '../core/app_lock.dart' show BiometricKind;
import 'gen/app_localizations.dart';

// Text that differs by platform. An iPhone never shows another platform's
// names (Apple guideline 2.3.10): no Google, Android or Play, no fingerprint
// where it has Face ID or Touch ID, and its passcode, not a "screen lock".
// Each Android-only key is read here and nowhere else; each has an iPhone
// twin (test/platform_text_test.dart scans the ARB and lib/ for both).

bool _iPhone(TargetPlatform platform) => platform == TargetPlatform.iOS;

/// Me → App lock's Face ID or Touch ID switch, and the lock screen's button:
/// an iPhone says Face ID or Touch ID, as the system does; before it has
/// answered ([kind] null), both. Everywhere else, the general words.
String lockUseLabel(
  AppLocalizations l10n,
  BiometricKind? kind,
  TargetPlatform platform,
) => switch (kind) {
  BiometricKind.faceId => l10n.lockUseFaceId,
  BiometricKind.touchId => l10n.lockUseTouchId,
  _ => _iPhone(platform) ? l10n.lockUseBiometricsIos : l10n.lockUseBiometrics,
};

/// Me → App lock's line. An iPhone with neither Face ID nor Touch ID set up
/// (or that hasn't answered yet) says the PIN only.
String lockHintLabel(
  AppLocalizations l10n,
  BiometricKind? kind,
  TargetPlatform platform,
) => switch (kind) {
  BiometricKind.faceId => l10n.meAppLockHintFaceId,
  BiometricKind.touchId => l10n.meAppLockHintTouchId,
  _ => _iPhone(platform) ? l10n.meAppLockHintIos : l10n.meAppLockHint,
};

/// Forgot PIN, with the phone's own lock: its screen lock, or the iPhone's
/// passcode.
String lockForgotBodyDevice(AppLocalizations l10n, TargetPlatform platform) =>
    _iPhone(platform) ? l10n.lockForgotBodyDeviceIos : l10n.lockForgotBodyDevice;

String lockForgotUseDevice(AppLocalizations l10n, TargetPlatform platform) =>
    _iPhone(platform) ? l10n.lockForgotUseDeviceIos : l10n.lockForgotUseDevice;

/// Forgot PIN, when the phone has no lock of its own: erase is the only way.
String lockForgotBodyEraseOnly(AppLocalizations l10n, TargetPlatform platform) =>
    _iPhone(platform)
    ? l10n.lockForgotBodyEraseOnlyIos
    : l10n.lockForgotBodyEraseOnly;

/// Privacy's first line: where the entries are. On an iPhone they're kept
/// out of every backup (decision 72), so it names no cloud but iCloud's.
String privacyStorage(AppLocalizations l10n, TargetPlatform platform) =>
    _iPhone(platform) ? l10n.privacy1Ios : l10n.privacy1;
