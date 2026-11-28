import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app lock (plan §3.11): a 4–6 digit PIN, optional fingerprint or face,
/// "lock after" a time away. The PIN is stored only as a salted PBKDF2 hash
/// in the platform keystore (secure storage, never backed up) and never
/// leaves the phone. Off until the person turns it on in Me.
enum LockAfter {
  immediately(Duration.zero),
  oneMinute(Duration(minutes: 1)),
  fiveMinutes(Duration(minutes: 5));

  const LockAfter(this.delay);
  final Duration delay;
}

/// Where the lock keeps its secrets (the keystore; a map in tests).
abstract interface class SecretStore {
  /// Every key, for every id (Delete everything).
  Future<void> deleteAll();
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class KeystoreSecretStore implements SecretStore {
  const KeystoreSecretStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class MemorySecretStore implements SecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();
}

/// Whether this install has run the lock before. The iOS Keychain survives
/// an uninstall (and a passed-on phone), SharedPreferences doesn't: a lock
/// found without the marker belongs to an earlier install and is cleared
/// (#50 review).
abstract interface class FirstRunMarker {
  Future<bool> seen();
  Future<void> markSeen();
}

class PrefsFirstRunMarker implements FirstRunMarker {
  const PrefsFirstRunMarker();

  static const _key = 'app_lock.installed';

  @override
  Future<bool> seen() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> markSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_key, true);
}

class MemoryFirstRunMarker implements FirstRunMarker {
  MemoryFirstRunMarker({this.wasSeen = true});

  bool wasSeen;

  @override
  Future<bool> seen() async => wasSeen;

  @override
  Future<void> markSeen() async => wasSeen = true;
}

enum BiometricKind { faceId, touchId, other }

/// Fingerprint / face, when the device has them enrolled.
abstract interface class Biometrics {
  Future<bool> available();

  /// True when the user passed; false when they cancelled or failed.
  Future<bool> authenticate(String reason);

  /// What this iPhone has set up, so the app can say Face ID or Touch ID.
  /// [BiometricKind.other] everywhere else, and on an iPhone with neither set
  /// up, where naming one could be wrong.
  Future<BiometricKind> kind();

  /// Whether the phone has a screen lock of its own (a PIN, pattern or
  /// password, or a fingerprint or face), so Forgot PIN can ask for it.
  Future<bool> screenLockSet();

  /// The phone's own screen lock, whichever kind it has (decision 19): true
  /// when the person passed, false when they cancelled or failed.
  Future<bool> authenticateWithScreenLock(String reason);
}

class DeviceBiometrics implements Biometrics {
  DeviceBiometrics();

  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> screenLockSet() async {
    try {
      // Android: the keyguard is secure or biometrics are enrolled; iOS: a
      // passcode is set.
      return await _auth.isDeviceSupported();
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticateWithScreenLock(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          // The phone's PIN, pattern or password counts, not only a finger
          // or a face.
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } on Object {
      return false;
    }
  }

  @override
  Future<BiometricKind> kind() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return BiometricKind.other;
    try {
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.face)) return BiometricKind.faceId;
      if (types.contains(BiometricType.fingerprint)) {
        return BiometricKind.touchId;
      }
      return BiometricKind.other;
    } on Object {
      return BiometricKind.other;
    }
  }
}

/// PBKDF2-HMAC-SHA256 ([iterations] rounds, 32 bytes).
@visibleForTesting
List<int> pbkdf2(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  final block = Uint8List.fromList([...salt, 0, 0, 0, 1]);
  var u = hmac.convert(block).bytes;
  final out = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

class AppLock extends ChangeNotifier {
  AppLock({
    required this.store,
    required this.biometrics,
    FirstRunMarker? firstRun,
    DateTime Function()? now,
    this.iterations = 60000,
  }) : firstRun = firstRun ?? MemoryFirstRunMarker(),
       _now = now ?? DateTime.now;

  final SecretStore store;
  final Biometrics biometrics;
  final FirstRunMarker firstRun;
  final DateTime Function() _now;

  /// PBKDF2 rounds (tests use fewer).
  final int iterations;

  /// The lock belongs to this phone, not to an account (decision 70): one
  /// set of keys, all in secure storage.
  static const _kHash = 'app_lock.pin_hash';

  /// The salt's own key before row 19; read for an older PIN, then removed.
  static const _kSalt = 'app_lock.pin_salt';
  static const _kSettings = 'app_lock.settings';
  static const _kFails = 'app_lock.fails';

  /// The stored PIN since row 19: `v2:<salt b64>:<hash b64>` in pin_hash.
  static const _v2 = 'v2:';

  /// 5 wrong PINs → a 30 s wait, doubling after each further wrong one.
  static const maxTries = 5;
  static const firstWait = Duration(seconds: 30);

  bool _enabled = false;
  bool _biometricsOn = false;
  bool _mayResetPin = false;
  LockAfter _lockAfter = LockAfter.immediately;
  bool _locked = false;
  int _fails = 0;
  DateTime? _waitUntil;
  DateTime? _awaySince;

  /// A PIN being stored (the hash takes seconds on a slow phone): the lock
  /// counts as on from the moment the PIN is confirmed (row 18: leaving
  /// in that window came back unlocked).
  Future<void>? _arming;

  bool get enabled => _enabled;

  /// On, or being turned on: what leaving the app (and the cover) must
  /// follow. [enabled] stays false until the PIN is stored.
  bool get on => _enabled || _arming != null;
  bool get biometricsOn => _biometricsOn;
  LockAfter get lockAfter => _lockAfter;

  /// Forgot PIN: the phone's own screen lock let the person in, so a new PIN
  /// may be chosen ([resetPin]). Still locked until it is. Leaving the app
  /// takes it back.
  bool get mayResetPin => _mayResetPin;

  /// The lock screen is up.
  bool get locked => on && _locked;

  /// How long until another PIN may be tried; null when it may now. Wall
  /// clock on purpose: rolling the device clock back can skip the wait, a
  /// fair trade since the PIN never leaves the phone (#50 review).
  Duration? get waitRemaining {
    final until = _waitUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left > Duration.zero ? left : null;
  }

  /// Reads the stored state; a cold start with the lock on starts locked,
  /// so the lock is up before the first frame.
  Future<void> load() async {
    if (!await firstRun.seen()) {
      // A lock left in the keystore by an earlier install: not this one's.
      await clear();
      await firstRun.markSeen();
      return;
    }
    await _read();
  }

  /// Delete everything (plan §3.8), and Forgot PIN's erase after it: every
  /// PIN, setting and count this lock kept in secure storage. The lock is
  /// off afterwards.
  Future<void> eraseAll() async {
    await store.deleteAll();
    _resetMemory();
    notifyListeners();
  }

  void _resetMemory() {
    _enabled = false;
    _biometricsOn = false;
    _mayResetPin = false;
    _lockAfter = LockAfter.immediately;
    _locked = false;
    _fails = 0;
    _waitUntil = null;
    _awaySince = null;
  }

  Future<void> _read() async {
    _enabled = (await store.read(_kHash)) != null;
    final settings = await store.read(_kSettings);
    if (settings != null) {
      final s = jsonDecode(settings) as Map<String, dynamic>;
      _biometricsOn = s['biometrics'] == true;
      _lockAfter = LockAfter.values.firstWhere(
        (l) => l.name == s['lockAfter'],
        orElse: () => LockAfter.immediately,
      );
    }
    final fails = await store.read(_kFails);
    if (fails != null) {
      final f = jsonDecode(fails) as Map<String, dynamic>;
      _fails = f['count'] as int? ?? 0;
      final until = f['until'] as String?;
      _waitUntil = until == null ? null : DateTime.parse(until);
    }
    _locked = _enabled;
    notifyListeners();
  }

  static bool validPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  /// Off the UI isolate at the real round count (#50 review); inline for
  /// the small counts tests use.
  Future<String> _hash(String pin, List<int> salt) async {
    final password = utf8.encode(pin);
    final rounds = iterations;
    final key = rounds > 1000
        ? await Isolate.run(() => pbkdf2(password, salt, rounds))
        : pbkdf2(password, salt, rounds);
    return base64Encode(key);
  }

  /// Turns the lock on (or changes the PIN). Unlocked afterwards, unless
  /// the app left and came back while the PIN was being stored: then it's
  /// locked, and [unlockWithPin] waits for the stored PIN.
  Future<void> setPin(String pin) async {
    if (!validPin(pin)) throw ArgumentError('PIN must be 4–6 digits');
    final done = Completer<void>();
    _arming = done.future;
    _locked = false;
    try {
      final rnd = Random.secure();
      final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
      // Salt and hash in one value, one write (row 19): a new salt stored
      // before a failed hash write made the old PIN never match again.
      final hash = await _hash(pin, salt);
      await store.write(_kHash, '$_v2${base64Encode(salt)}:$hash');
      try {
        await store.delete(_kSalt); // the pre-row-19 separate salt
      } on Object {
        // Unused from now on; a later setPin or clear() removes it.
      }
      await _saveFails(0, null);
      _enabled = true;
      await _saveSettings();
    } finally {
      _arming = null;
      done.complete();
      notifyListeners();
    }
  }

  /// Checks [pin] while locked. Wrong ones count toward the wait.
  Future<bool> unlockWithPin(String pin) async {
    final ok = await _checkPin(pin);
    if (ok) _locked = false;
    notifyListeners();
    return ok;
  }

  Future<bool> _checkPin(String pin) async {
    final arming = _arming;
    if (arming != null) await arming;
    if (waitRemaining != null) return false;
    final stored = await store.read(_kHash);
    if (stored == null) return false;
    // "v2:<salt>:<hash>" since row 19; before it, the salt had its own key.
    final String? salt;
    final String hash;
    if (stored.startsWith(_v2)) {
      final parts = stored.substring(_v2.length).split(':');
      if (parts.length != 2) return false;
      salt = parts[0];
      hash = parts[1];
    } else {
      salt = await store.read(_kSalt);
      hash = stored;
    }
    if (salt == null) return false;
    final ok = await _hash(pin, base64Decode(salt)) == hash;
    if (ok) {
      await _saveFails(0, null);
    } else {
      final fails = _fails + 1;
      DateTime? until;
      if (fails >= maxTries) {
        final doublings = fails - maxTries;
        until = _now().add(firstWait * (1 << doublings.clamp(0, 10)));
      }
      await _saveFails(fails, until);
    }
    return ok;
  }

  Future<bool> unlockWithBiometrics(String reason) async {
    if (!_biometricsOn) return false;
    final ok = await biometrics.authenticate(reason);
    if (ok) {
      await _saveFails(0, null);
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  Future<void> setBiometrics({required bool on}) async {
    _biometricsOn = on;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setLockAfter(LockAfter value) async {
    _lockAfter = value;
    await _saveSettings();
    notifyListeners();
  }

  /// Forgot PIN's first path (decision 19): the phone's own screen lock. A
  /// pass lets a new PIN be chosen ([resetPin]); nothing is unlocked yet.
  Future<bool> verifyWithScreenLock(String reason) async {
    final ok = await biometrics.authenticateWithScreenLock(reason);
    _mayResetPin = ok && locked;
    notifyListeners();
    return _mayResetPin;
  }

  /// Forgot PIN's erase is running: the lock screen stays up until it's
  /// done, even after the PIN is gone, so a step that still fails is said
  /// there ("Not everything was erased") and never skipped.
  bool get erasing => _erasing;
  bool _erasing = false;

  void setErasing({required bool on}) {
    if (_erasing == on) return;
    _erasing = on;
    notifyListeners();
  }

  /// Leaves the new-PIN step for the PIN pad, without a new PIN.
  void cancelResetPin() {
    if (!_mayResetPin) return;
    _mayResetPin = false;
    notifyListeners();
  }

  /// The new PIN after the phone's screen lock let the person in: stored in
  /// place of the forgotten one, the wrong tries forgotten, and unlocked.
  /// Only after [verifyWithScreenLock] passed.
  Future<void> resetPin(String pin) async {
    if (!_mayResetPin) {
      throw StateError("A new PIN only after the phone's screen lock");
    }
    await setPin(pin);
    _mayResetPin = false;
    notifyListeners();
  }

  /// Off: the PIN and settings are erased (Me → App lock off).
  Future<void> clear() async {
    // A PIN still being stored lands first, then goes: otherwise its write
    // could follow the erase and turn the lock back on (review N5).
    final arming = _arming;
    if (arming != null) await arming;
    for (final k in [_kHash, _kSalt, _kSettings, _kFails]) {
      await store.delete(k);
    }
    _resetMemory();
    notifyListeners();
  }

  /// Opened from the home-screen widget: the lock screen first, whatever
  /// "lock after" says (decision 174).
  void lockNow() {
    if (!on || _locked) return;
    _locked = true;
    notifyListeners();
  }

  /// The app went to the background. A new PIN not yet chosen after the
  /// phone's screen lock has to wait for it again.
  void wentAway() {
    _awaySince ??= _now();
    if (_mayResetPin) {
      _mayResetPin = false;
      notifyListeners();
    }
  }

  /// The app came back: locks when it was away at least [lockAfter].
  void cameBack() {
    final since = _awaySince;
    _awaySince = null;
    if (!on || since == null) return;
    if (_now().difference(since) >= _lockAfter.delay) {
      _locked = true;
      notifyListeners();
    }
  }

  Future<void> _saveSettings() => store.write(
    _kSettings,
    jsonEncode({
      'biometrics': _biometricsOn,
      'lockAfter': _lockAfter.name,
    }),
  );

  Future<void> _saveFails(int count, DateTime? until) {
    _fails = count;
    _waitUntil = until;
    return store.write(
      _kFails,
      jsonEncode({'count': count, 'until': until?.toIso8601String()}),
    );
  }
}
