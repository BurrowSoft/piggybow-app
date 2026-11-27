import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/app_lock.dart';

import 'app_lock_test.dart' show FakeBiometrics;

/// App lock belongs to the account on this
/// phone. Signing out keeps it; the same account back = the lock back on;
/// another account starts with it off; delete account clears it.
void main() {
  late MemorySecretStore store;
  AppLock make() => AppLock(
    store: store,
    biometrics: FakeBiometrics(),
    firstRun: MemoryFirstRunMarker()..wasSeen = true,
    iterations: 50,
  );

  setUp(() => store = MemorySecretStore());

  test('keys carry the account; signing out keeps them', () async {
    final lock = make();
    await lock.load(userId: 'a');
    await lock.setPin('2468');
    expect(store.values['app_lock.a.pin_hash'], isNotNull);
    expect(store.values['app_lock.pin_hash'], isNull);

    await lock.switchUser(null); // signed out
    expect(lock.enabled, isFalse);
    expect(store.values['app_lock.a.pin_hash'], isNotNull);
  });

  test(
    'the same account back: on (unlocked just after the password)',
    () async {
      final lock = make();
      await lock.load(userId: 'a');
      await lock.setPin('2468');
      await lock.switchUser(null);
      await lock.switchUser('a');
      expect(lock.enabled, isTrue);
      expect(lock.locked, isFalse);
      expect(await lock.unlockWithPin('2468'), isTrue, reason: 'same PIN');
    },
  );

  test('another account starts with it off, its own once set', () async {
    final lock = make();
    await lock.load(userId: 'a');
    await lock.setPin('2468');
    await lock.switchUser(null);
    await lock.switchUser('b');
    expect(lock.enabled, isFalse);
    await lock.setPin('1357');
    await lock.switchUser('a');
    expect(lock.enabled, isTrue);
    expect(store.values['app_lock.b.pin_hash'], isNotNull);
  });

  test('a cold start with the account\'s lock on starts locked', () async {
    final first = make();
    await first.load(userId: 'a');
    await first.setPin('2468');
    final again = make();
    await again.load(userId: 'a');
    expect(again.locked, isTrue);
  });

  test('delete account forgets that account\'s lock only', () async {
    final lock = make();
    await lock.load(userId: 'a');
    await lock.setPin('2468');
    await lock.switchUser('b');
    await lock.setPin('1357');
    await lock.forget('a');
    expect(
      store.values.keys.where((k) => k.startsWith('app_lock.a.')),
      isEmpty,
    );
    expect(store.values['app_lock.b.pin_hash'], isNotNull);
    expect(lock.enabled, isTrue, reason: 'b is still on');
  });

  test('review: an account signing in after the upgrade never inherits the '
      '0.9.1 lock; the old keys are discarded', () async {
    final old = make();
    await old.load(); // 0.9.1: no account in the keys
    await old.setPin('2468');

    final upgraded = make();
    await upgraded.load(); // signed out at the upgrade: no account
    await upgraded.switchUser('b'); // then someone signs in
    expect(upgraded.enabled, isFalse);
    expect(store.values['app_lock.pin_hash'], isNull);
    expect(store.values['app_lock.b.pin_hash'], isNull);
    expect(await upgraded.unlockWithPin('2468'), isFalse);
  });

  test('a lock from 0.9.1 (device-wide keys) is adopted by the account '
      'signed in at the upgrade', () async {
    final old = make();
    await old.load(); // 0.9.1: no account in the keys
    await old.setPin('2468');
    expect(store.values['app_lock.pin_hash'], isNotNull);

    final upgraded = make();
    await upgraded.load(userId: 'a');
    expect(upgraded.enabled, isTrue);
    expect(store.values['app_lock.pin_hash'], isNull);
    expect(store.values['app_lock.a.pin_hash'], isNotNull);
    await upgraded.switchUser(null);
    expect(await upgraded.unlockWithPin('2468'), isFalse);
    await upgraded.switchUser('a');
    expect(await upgraded.unlockWithPin('2468'), isTrue);
  });
}
