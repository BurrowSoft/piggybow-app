import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';

class FakeBiometrics implements Biometrics {
  bool has = true;
  bool pass = true;
  BiometricKind kindIs = BiometricKind.other;
  int asked = 0;

  @override
  Future<bool> available() async => has;

  @override
  Future<bool> authenticate(String reason) async {
    asked++;
    return pass;
  }

  @override
  Future<BiometricKind> kind() async => kindIs;
}

/// Writes held from [close] until [open]: the PIN "still being stored"
/// (row 18).
class GatedStore extends MemorySecretStore {
  Completer<void>? _gate;

  void close() => _gate = Completer<void>();
  void open() => _gate?.complete();

  @override
  Future<void> write(String key, String value) async {
    await _gate?.future;
    await super.write(key, value);
  }
}

/// A write to [failKey] throws (a full or failing keystore), once armed.
class FailingStore extends MemorySecretStore {
  String? failKey;

  @override
  Future<void> write(String key, String value) async {
    if (key == failKey) throw StateError('write failed');
    await super.write(key, value);
  }
}

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  var now = DateTime.utc(2026, 10, 20, 9);
  late MemorySecretStore store;
  late FakeBiometrics bio;
  AppLock make() =>
      AppLock(store: store, biometrics: bio, now: () => now, iterations: 50);

  setUp(() {
    now = DateTime.utc(2026, 10, 20, 9);
    store = MemorySecretStore();
    bio = FakeBiometrics();
  });

  test('PBKDF2-HMAC-SHA256 matches the RFC 7914 vectors', () {
    expect(
      hex(pbkdf2(utf8.encode('password'), utf8.encode('salt'), 1)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      hex(pbkdf2(utf8.encode('password'), utf8.encode('salt'), 2)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
  });

  test(
    'off by default; a PIN turns it on, stored only as a salted hash',
    () async {
      final lock = make();
      await lock.load();
      expect(lock.enabled, isFalse);
      expect(lock.locked, isFalse);
      await lock.setPin('2468');
      expect(lock.enabled, isTrue);
      expect(lock.locked, isFalse, reason: 'just set: not locked');
      expect(store.values.values.join(), isNot(contains('2468')));
      // Salt and hash in one value (row 19).
      expect(store.values['app_lock.pin_hash'], startsWith('v2:'));
      expect(store.values['app_lock.pin_salt'], isNull);
    },
  );

  group('row 18: leaving while the PIN is still being stored', () {
    late GatedStore gated;
    AppLock makeGated() =>
        AppLock(store: gated, biometrics: bio, now: () => now, iterations: 50);
    setUp(() => gated = GatedStore()..close());

    test('comes back locked; the PIN opens it once stored', () async {
      final lock = makeGated();
      final setting = lock.setPin('2468');
      // The PIN confirmed, its hash not written yet: Home, then back.
      lock
        ..wentAway()
        ..cameBack();
      expect(lock.locked, isTrue, reason: 'armed from the confirm');
      gated.open();
      await setting;
      expect(lock.enabled, isTrue);
      expect(lock.locked, isTrue, reason: 'still locked once stored');
      expect(await lock.unlockWithPin('1357'), isFalse);
      expect(await lock.unlockWithPin('2468'), isTrue);
      expect(lock.locked, isFalse);
    });

    test('a PIN typed before the store finishes waits for it', () async {
      final lock = makeGated();
      final setting = lock.setPin('2468');
      lock
        ..wentAway()
        ..cameBack();
      final unlocking = lock.unlockWithPin('2468');
      gated.open();
      expect(await unlocking, isTrue);
      await setting;
      expect(lock.locked, isFalse);
    });

    test('staying in the app: on and unlocked, as before', () async {
      final lock = makeGated();
      final setting = lock.setPin('2468');
      expect(lock.locked, isFalse);
      gated.open();
      await setting;
      expect(lock.enabled, isTrue);
      expect(lock.locked, isFalse);
    });

    test('"Forgot PIN?" while storing: erased, and stays off', () async {
      final lock = makeGated();
      final setting = lock.setPin('2468');
      lock
        ..wentAway()
        ..cameBack();
      expect(lock.locked, isTrue);
      final clearing = lock.clear();
      gated.open();
      await Future.wait([setting, clearing]);
      expect(lock.enabled, isFalse);
      expect(lock.locked, isFalse);
      expect(gated.values, isEmpty, reason: 'nothing written after the erase');
    });

    test('changing the PIN: "lock after 1 minute" still applies', () async {
      gated.open();
      final lock = makeGated();
      await lock.setPin('1111');
      await lock.setLockAfter(LockAfter.oneMinute);
      gated.close();
      final changing = lock.setPin('2468');
      lock.wentAway();
      now = now.add(const Duration(seconds: 30));
      lock.cameBack();
      expect(lock.locked, isFalse, reason: '30 s < 1 min');
      lock.wentAway();
      now = now.add(const Duration(minutes: 1));
      lock.cameBack();
      expect(lock.locked, isTrue, reason: '1 min');
      gated.open();
      await changing;
      expect(await lock.unlockWithPin('2468'), isTrue, reason: 'the new PIN');
    });
  });

  group('row 19: a PIN change that fails to store', () {
    test('the old PIN still opens it', () async {
      final failing = FailingStore();
      final lock = AppLock(
        store: failing,
        biometrics: bio,
        now: () => now,
        iterations: 50,
      );
      await lock.setPin('2468');
      failing.failKey = 'app_lock.pin_hash';
      await expectLater(lock.setPin('1357'), throwsStateError);
      expect(lock.enabled, isTrue);
      lock
        ..wentAway()
        ..cameBack();
      expect(lock.locked, isTrue);
      expect(await lock.unlockWithPin('1357'), isFalse);
      expect(await lock.unlockWithPin('2468'), isTrue, reason: 'old PIN');
    });

    test('a PIN stored before row 19 (separate salt) still opens it, '
        'and the next one is stored in one value', () async {
      await make().setPin('9999');
      final salt = List<int>.generate(16, (i) => i);
      store.values['app_lock.pin_salt'] = base64Encode(salt);
      store.values['app_lock.pin_hash'] = base64Encode(
        pbkdf2(utf8.encode('2468'), salt, 50),
      );
      final lock = make();
      await lock.load();
      expect(lock.locked, isTrue);
      expect(await lock.unlockWithPin('9999'), isFalse);
      expect(await lock.unlockWithPin('2468'), isTrue);
      await lock.setPin('1357');
      expect(store.values['app_lock.pin_hash'], startsWith('v2:'));
      expect(store.values['app_lock.pin_salt'], isNull);
      lock
        ..wentAway()
        ..cameBack();
      expect(await lock.unlockWithPin('1357'), isTrue);
    });
  });

  test('only 4–6 digits', () async {
    final lock = make();
    for (final bad in ['123', '1234567', '12a4', '']) {
      expect(() => lock.setPin(bad), throwsArgumentError, reason: bad);
    }
  });

  test(
    'a cold start with the lock on starts locked; the PIN opens it',
    () async {
      await make().setPin('2468');
      final lock = make();
      await lock.load();
      expect(lock.locked, isTrue);
      expect(await lock.unlockWithPin('1357'), isFalse);
      expect(lock.locked, isTrue);
      expect(await lock.unlockWithPin('2468'), isTrue);
      expect(lock.locked, isFalse);
    },
  );

  test('5 wrong tries → a 30 s wait, doubling; the right PIN resets', () async {
    final lock = make();
    await lock.setPin('2468');
    lock
      ..wentAway()
      ..cameBack();
    for (var i = 0; i < 4; i++) {
      expect(await lock.unlockWithPin('0000'), isFalse);
      expect(lock.waitRemaining, isNull, reason: 'try ${i + 1}');
    }
    expect(await lock.unlockWithPin('0000'), isFalse);
    expect(lock.waitRemaining, const Duration(seconds: 30));
    // Even the right PIN waits.
    expect(await lock.unlockWithPin('2468'), isFalse);
    now = now.add(const Duration(seconds: 31));
    expect(await lock.unlockWithPin('0000'), isFalse);
    expect(lock.waitRemaining, const Duration(seconds: 60), reason: 'doubled');
    now = now.add(const Duration(seconds: 61));
    expect(await lock.unlockWithPin('2468'), isTrue);
    expect(lock.waitRemaining, isNull);
    // The count restarts after a success.
    lock
      ..wentAway()
      ..cameBack();
    expect(await lock.unlockWithPin('0000'), isFalse);
    expect(lock.waitRemaining, isNull);
  });

  test('the wait survives a restart', () async {
    final lock = make();
    await lock.setPin('2468');
    for (var i = 0; i < 5; i++) {
      await lock.unlockWithPin('0000');
    }
    final again = make();
    await again.load();
    expect(again.waitRemaining, const Duration(seconds: 30));
  });

  test('lock after: immediately, 1 minute, 5 minutes away', () async {
    final lock = make();
    await lock.setPin('2468');
    lock
      ..wentAway()
      ..cameBack();
    expect(lock.locked, isTrue, reason: 'immediately');
    await lock.unlockWithPin('2468');

    await lock.setLockAfter(LockAfter.oneMinute);
    lock.wentAway();
    now = now.add(const Duration(seconds: 59));
    lock.cameBack();
    expect(lock.locked, isFalse, reason: '59 s < 1 min');
    lock.wentAway();
    now = now.add(const Duration(minutes: 1));
    lock.cameBack();
    expect(lock.locked, isTrue, reason: '1 min');
  });

  test('biometrics: only when turned on; a pass unlocks', () async {
    final lock = make();
    await lock.setPin('2468');
    lock
      ..wentAway()
      ..cameBack();
    expect(await lock.unlockWithBiometrics('Unlock'), isFalse);
    expect(bio.asked, 0);
    await lock.setBiometrics(on: true);
    bio.pass = false;
    expect(await lock.unlockWithBiometrics('Unlock'), isFalse);
    expect(lock.locked, isTrue);
    bio.pass = true;
    expect(await lock.unlockWithBiometrics('Unlock'), isTrue);
    expect(lock.locked, isFalse);
  });

  test('a lock left by an earlier install (iOS Keychain) is cleared on the '
      'first run', () async {
    await make().setPin('2468');
    final marker = MemoryFirstRunMarker(wasSeen: false);
    final fresh = AppLock(
      store: store,
      biometrics: bio,
      firstRun: marker,
      iterations: 50,
    );
    await fresh.load();
    expect(fresh.enabled, isFalse);
    expect(fresh.locked, isFalse);
    expect(store.values, isEmpty);
    expect(marker.wasSeen, isTrue);
    // From then on the lock works as usual.
    await fresh.setPin('1357');
    final again = AppLock(
      store: store,
      biometrics: bio,
      firstRun: marker,
      iterations: 50,
    );
    await again.load();
    expect(again.locked, isTrue);
  });

  test('clear (off / sign-out) erases the PIN and settings', () async {
    final lock = make();
    await lock.setPin('2468');
    await lock.setBiometrics(on: true);
    await lock.clear();
    expect(lock.enabled, isFalse);
    expect(store.values, isEmpty);
    final again = make();
    await again.load();
    expect(again.locked, isFalse);
  });
}
