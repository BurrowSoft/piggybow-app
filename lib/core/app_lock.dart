import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 1.1 C, app lock (specs/1.1-features.md; decision 171): a 4–6 digit PIN,
/// optional biometrics, "lock after" a time away. The PIN is stored only as a
/// salted PBKDF2 hash in the platform keystore and never leaves the phone.
/// Off by default; behind AppConfig.appLockEnabled until it's released.
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

  /// App lock belongs to the account on this phone, so
  /// its keys carry the user id (`app_lock.<uid>.pin_hash`). Without one
  /// (no account known yet, tests): the pre-0.9.2 device-wide keys, which
  /// the first account to load them adopts.
  String? _uid;
  static String _key(String? uid, String name) =>
      uid == null ? 'app_lock.$name' : 'app_lock.$uid.$name';
  static const _names = ['pin_hash', 'pin_salt', 'settings', 'fails'];
  String get _kHash => _key(_uid, 'pin_hash');
  String get _kSalt => _key(_uid, 'pin_salt');

  /// The stored PIN since row 19: `v2:<salt b64>:<hash b64>` in pin_hash.
  static const _v2 = 'v2:';
  String get _kSettings => _key(_uid, 'settings');
  String get _kFails => _key(_uid, 'fails');

  /// The account changed and its settings are being read: LockGate covers
  /// the app meanwhile, so the journal never shows before the lock.
  bool get switching => _switching;
  bool _switching = false;

  /// 5 wrong PINs → a 30 s wait, doubling after each further wrong one.
  static const maxTries = 5;
  static const firstWait = Duration(seconds: 30);

  bool _enabled = false;
  bool _biometricsOn = false;
  bool _planWhenLocked = false;
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

  /// 1.2: the lock screen's help card may open My safety plan, read-only
  /// (Me → App lock, "Show my safety plan without unlocking"). Off by
  /// default; turning it on asks for the PIN first; off with the lock.
  bool get planWhenLocked => _enabled && _planWhenLocked;
  LockAfter get lockAfter => _lockAfter;

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

  /// Reads the stored state; a cold start with the lock on starts locked.
  /// [userId]: the account whose lock this is (the stored session's at a
  /// cold start), so the lock is up before the first frame.
  Future<void> load({String? userId}) async {
    _uid = userId;
    if (!await firstRun.seen()) {
      // A lock left in the keystore by an earlier install: not this one's.
      await clear();
      await firstRun.markSeen();
      return;
    }
    // A cold start with a stored session: the account that was signed in
    // when 0.9.1 set the device-wide lock.
    await _readCurrent(adoptLegacy: true);
  }

  /// Another account (or none) on this phone: its own lock, or none.
  /// Nothing is erased; signing out keeps each account's lock (M-02).
  Future<void> switchUser(String? userId) async {
    if (userId == _uid) return;
    _switching = true;
    notifyListeners();
    _uid = userId;
    _resetMemory();
    try {
      if (userId != null) {
        await _readCurrent();
        // Just signed in with the password: on, but not asked for the PIN
        // right away; it locks the next time the app comes back.
        _locked = false;
      }
    } finally {
      _switching = false;
      notifyListeners();
    }
  }

  /// Delete account (or the account deleted elsewhere): that account's lock
  /// goes with it.
  Future<void> forget(String userId) async {
    for (final n in _names) {
      await store.delete(_key(userId, n));
    }
    if (_uid == userId) {
      _resetMemory();
      notifyListeners();
    }
  }

  /// Delete everything (plan §3.8): every PIN, setting and count this lock
  /// kept in secure storage, for every id, legacy ones included. The lock
  /// is off afterwards.
  Future<void> eraseAll() async {
    await store.deleteAll();
    _resetMemory();
    notifyListeners();
  }

  void _resetMemory() {
    _enabled = false;
    _biometricsOn = false;
    _planWhenLocked = false;
    _lockAfter = LockAfter.immediately;
    _locked = false;
    _fails = 0;
    _waitUntil = null;
    _awaySince = null;
  }

  /// The current account's stored lock. The pre-0.9.2 device-wide one is
  /// adopted only by [adoptLegacy]: the cold start of a session that was
  /// already signed in when 0.9.1 set it. Any other account (a sign-in
  /// after the upgrade) must never inherit someone else's PIN (UX, review):
  /// the old keys are then discarded.
  Future<void> _readCurrent({bool adoptLegacy = false}) async {
    final uid = _uid;
    final legacyHash = await store.read(_key(null, 'pin_hash'));
    if (uid != null && legacyHash != null) {
      final adopt = adoptLegacy && await store.read(_kHash) == null;
      for (final n in _names) {
        final v = await store.read(_key(null, n));
        if (adopt && v != null) await store.write(_key(uid, n), v);
        await store.delete(_key(null, n));
      }
    }
    _enabled = (await store.read(_kHash)) != null;
    final settings = await store.read(_kSettings);
    if (settings != null) {
      final s = jsonDecode(settings) as Map<String, dynamic>;
      _biometricsOn = s['biometrics'] == true;
      _planWhenLocked = s['planWhenLocked'] == true;
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

  /// The person confirms it's them (turning on "without unlocking"):
  /// [unlockWithPin]'s check and wait, without unlocking anything.
  Future<bool> confirmPin(String pin) async {
    final ok = await _checkPin(pin);
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

  Future<void> setPlanWhenLocked({required bool on}) async {
    _planWhenLocked = on;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setLockAfter(LockAfter value) async {
    _lockAfter = value;
    await _saveSettings();
    notifyListeners();
  }

  /// Off: this account's PIN and settings are erased (Me → App lock off,
  /// and "Forgot PIN?" before it signs out). A plain sign-out keeps them.
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

  /// The app went to the background.
  void wentAway() => _awaySince ??= _now();

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
      'planWhenLocked': _planWhenLocked,
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
